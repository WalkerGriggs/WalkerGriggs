//! A compact Markdown subset → HTML renderer. Footnotes become Tufte sidenotes (`[^mn…]` → margin notes).
//! Blocks: headings, paragraphs, fenced code, blockquotes, flat lists, rules, raw HTML.
//! Inline: code, strong, em, links, images, autolinks, inline HTML, entities.
const std = @import("std");
const Writer = std.Io.Writer;

pub const Doc = struct { html: []const u8, excerpt: []const u8 };

const Renderer = struct {
    arena: std.mem.Allocator,
    w: *Writer,
    notes: std.StringHashMapUnmanaged([]const u8) = .empty,
    note_count: usize = 0,
    buf: std.ArrayList(u8) = .empty, // text of the open paragraph or list item
    list: ?u8 = null, // 'u' or 'o'
    quote: bool = false,
    excerpt: ?[]const u8 = null,

    fn flushText(r: *Renderer) !void {
        if (r.buf.items.len == 0) return;
        const tag = if (r.list != null) "li" else "p";
        try r.w.print("<{s}>", .{tag});
        try r.inline_(r.w, r.buf.items, true);
        try r.w.print("</{s}>\n", .{tag});
        if (r.excerpt == null and r.list == null and !r.quote) {
            var plain: Writer.Allocating = .init(r.arena);
            try r.inline_(&plain.writer, r.buf.items, false);
            r.excerpt = try text(r.arena, plain.written());
        }
        r.buf.clearRetainingCapacity();
    }

    fn closeBlocks(r: *Renderer) !void {
        try r.flushText();
        if (r.list) |l| try r.w.print("</{c}l>\n", .{l});
        if (r.quote) try r.w.writeAll("</blockquote>\n");
        r.list = null;
        r.quote = false;
    }

    fn inline_(r: *Renderer, w: *Writer, s: []const u8, notes: bool) Writer.Error!void {
        var strong = false;
        var em = false;
        var i: usize = 0;
        while (i < s.len) : (i += 1) {
            const c = s[i];
            const rest = s[i..];
            if (c == '\\' and i + 1 < s.len and std.ascii.isPrint(s[i + 1])) {
                i += 1;
                try escape(s[i .. i + 1], w);
            } else if (c == '`') {
                const end = std.mem.indexOfScalarPos(u8, s, i + 1, '`') orelse s.len;
                try w.writeAll("<code>");
                try escape(s[i + 1 .. end], w);
                try w.writeAll("</code>");
                i = end;
            } else if (std.mem.startsWith(u8, rest, "[^")) {
                const end = std.mem.indexOfScalarPos(u8, s, i, ']') orelse s.len;
                defer i = end;
                if (!notes) continue;
                const id = s[i + 2 .. end];
                const note = r.notes.get(id) orelse "";
                r.note_count += 1;
                const margin = std.mem.startsWith(u8, id, "mn");
                try w.print("<label for=\"sn-{d}\" class=\"margin-toggle{s}\">{s}</label><input type=\"checkbox\" id=\"sn-{d}\" class=\"margin-toggle\"/><span class=\"{s}\">", .{
                    r.note_count, if (margin) "" else " sidenote-number", if (margin) "&#8853;" else "", r.note_count, if (margin) "marginnote" else "sidenote",
                });
                try r.inline_(w, note, false);
                try w.writeAll("</span>");
            } else if (link(rest, c == '!')) |l| {
                if (c == '!') {
                    try w.print("<img src=\"{f}\" alt=\"{f}\" loading=\"lazy\">", .{ attr(l.href), attr(l.text) });
                } else {
                    try w.print("<a href=\"{f}\">", .{attr(l.href)});
                    try r.inline_(w, l.text, notes);
                    try w.writeAll("</a>");
                }
                i += l.len - 1;
            } else if (c == '<' and std.mem.startsWith(u8, rest, "<http") and std.mem.indexOfScalar(u8, rest, '>') != null) {
                const url = rest[1..std.mem.indexOfScalar(u8, rest, '>').?];
                try w.print("<a href=\"{f}\">{f}</a>", .{ attr(url), attr(url) });
                i += url.len + 1;
            } else if (c == '<' and i + 1 < s.len and (std.ascii.isAlphabetic(s[i + 1]) or s[i + 1] == '/' or s[i + 1] == '!')) {
                const end = std.mem.indexOfScalarPos(u8, s, i, '>') orelse s.len - 1;
                if (notes) try w.writeAll(s[i .. end + 1]); // inline HTML passes through (dropped from plain text)
                i = end;
            } else if ((std.mem.startsWith(u8, rest, "**") or std.mem.startsWith(u8, rest, "__")) and (strong or std.mem.indexOfPos(u8, s, i + 2, rest[0..2]) != null)) {
                strong = !strong;
                try w.writeAll(if (strong) "<strong>" else "</strong>");
                i += 1;
            } else if ((c == '*' or (c == '_' and (if (em) i + 1 == s.len or !std.ascii.isAlphanumeric(s[i + 1]) else i == 0 or !std.ascii.isAlphanumeric(s[i - 1])))) and
                (em or std.mem.indexOfScalarPos(u8, s, i + 1, c) != null))
            {
                em = !em;
                try w.writeAll(if (em) "<em>" else "</em>");
            } else if (c == '&' and entity(rest)) {
                try w.writeByte('&');
            } else try escape(s[i .. i + 1], w);
        }
    }
};

pub fn render(arena: std.mem.Allocator, src: []const u8) !Doc {
    var out: Writer.Allocating = .init(arena);
    var r: Renderer = .{ .arena = arena, .w = &out.writer };
    var lines = std.mem.splitScalar(u8, src, '\n');
    while (lines.next()) |line| if (std.mem.startsWith(u8, line, "[^")) if (std.mem.indexOf(u8, line, "]:")) |e|
        try r.notes.put(arena, line[2..e], std.mem.trim(u8, line[e + 2 ..], " \t\r"));

    var code = false;
    var raw = false;
    lines.reset();
    while (lines.next()) |l| {
        const line = std.mem.trimEnd(u8, l, " \t\r");
        const t = std.mem.trimStart(u8, line, " \t");
        if (code) {
            if (std.mem.startsWith(u8, t, "```")) {
                code = false;
                try r.w.writeAll("</code></pre>\n");
            } else {
                try escape(line, r.w);
                try r.w.writeByte('\n');
            }
        } else if (std.mem.startsWith(u8, t, "```")) {
            try r.closeBlocks();
            code = true;
            const lang = std.mem.trim(u8, t[3..], " ");
            if (lang.len > 0) try r.w.print("<pre><code class=\"language-{f}\">", .{attr(lang)}) else try r.w.writeAll("<pre><code>");
        } else if (t.len == 0) {
            try r.closeBlocks();
            raw = false;
        } else if (raw or (t[0] == '<' and r.buf.items.len == 0 and r.list == null and !std.mem.startsWith(u8, t, "<http"))) {
            raw = true;
            try r.w.print("{s}\n", .{line});
        } else if (std.mem.startsWith(u8, t, "[^") and std.mem.indexOf(u8, t, "]:") != null) {
            continue;
        } else if (heading(t)) |level| {
            try r.closeBlocks();
            const h = @max(level, 2); // the page title is the only <h1>
            const body = std.mem.trim(u8, t[level..], " #");
            try r.w.print("<h{d} id=\"{s}\">", .{ h, try slug(arena, body) });
            try r.inline_(r.w, body, true);
            try r.w.print("</h{d}>\n", .{h});
        } else if (t.len >= 3 and std.mem.count(u8, t, t[0..1]) == t.len and std.mem.indexOfScalar(u8, "-*_", t[0]) != null) {
            try r.closeBlocks();
            try r.w.writeAll("<hr>\n");
        } else if (t[0] == '>') {
            if (!r.quote) {
                try r.closeBlocks();
                try r.w.writeAll("<blockquote>\n");
                r.quote = true;
            }
            const q = std.mem.trimStart(u8, t[1..], " ");
            if (q.len == 0) try r.flushText() else try appendText(&r, q);
        } else if (listItem(t)) |item| {
            try r.flushText();
            if (r.list != item.kind) {
                try r.closeBlocks();
                try r.w.print("<{c}l>\n", .{item.kind});
                r.list = item.kind;
            }
            try appendText(&r, item.text);
        } else try appendText(&r, t);
    }
    if (code) try r.w.writeAll("</code></pre>\n");
    try r.closeBlocks();
    return .{ .html = out.written(), .excerpt = r.excerpt orelse "" };
}

fn appendText(r: *Renderer, s: []const u8) !void {
    if (r.buf.items.len > 0) try r.buf.append(r.arena, ' ');
    try r.buf.appendSlice(r.arena, s);
}

fn heading(t: []const u8) ?usize {
    const n = std.mem.indexOfNone(u8, t, "#") orelse return null;
    return if (n >= 1 and n <= 6 and t[n] == ' ') n else null;
}

fn listItem(t: []const u8) ?struct { kind: u8, text: []const u8 } {
    if (t.len > 2 and std.mem.indexOfScalar(u8, "-*+", t[0]) != null and t[1] == ' ') return .{ .kind = 'u', .text = t[2..] };
    const n = std.mem.indexOfNone(u8, t, "0123456789") orelse return null;
    return if (n > 0 and n + 1 < t.len and (t[n] == '.' or t[n] == ')') and t[n + 1] == ' ') .{ .kind = 'o', .text = t[n + 2 ..] } else null;
}

/// Parses `[text](href "title")` (or `![…](…)` when `image`) at the start of `s`.
fn link(s: []const u8, image: bool) ?struct { text: []const u8, href: []const u8, len: usize } {
    const o: usize = @intFromBool(image);
    if (s.len < o + 4 or s[o] != '[') return null;
    const close = std.mem.indexOf(u8, s, "](") orelse return null;
    const end = std.mem.indexOfScalarPos(u8, s, close, ')') orelse return null;
    const target = s[close + 2 .. end];
    return .{ .text = s[o + 1 .. close], .href = target[0 .. std.mem.indexOfScalar(u8, target, ' ') orelse target.len], .len = end + 1 };
}

fn entity(s: []const u8) bool {
    const semi = std.mem.indexOfScalar(u8, s[0..@min(s.len, 10)], ';') orelse return false;
    for (s[1..semi]) |ch| if (!std.ascii.isAlphanumeric(ch) and ch != '#') return false;
    return semi > 1;
}

pub fn escape(s: []const u8, w: *Writer) Writer.Error!void {
    for (s) |c| switch (c) {
        '&' => try w.writeAll("&amp;"),
        '<' => try w.writeAll("&lt;"),
        '>' => try w.writeAll("&gt;"),
        '"' => try w.writeAll("&quot;"),
        else => try w.writeByte(c),
    };
}

/// `{f}` formatter that HTML/XML-escapes a string.
pub fn attr(s: []const u8) std.fmt.Alt([]const u8, escape) {
    return .{ .data = s };
}

/// Lower-case, hyphen-separated identifier (heading anchors, tag paths).
pub fn slug(arena: std.mem.Allocator, s: []const u8) ![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    for (s) |c| if (std.ascii.isAlphanumeric(c)) try out.append(arena, std.ascii.toLower(c)) else if (out.items.len > 0 and out.items[out.items.len - 1] != '-') try out.append(arena, '-');
    return std.mem.trimEnd(u8, out.items, "-");
}

/// Strips tags and decodes the basic entities, leaving plain text.
pub fn text(arena: std.mem.Allocator, html: []const u8) ![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    var i: usize = 0;
    while (i < html.len) : (i += 1) switch (html[i]) {
        '<' => i = std.mem.indexOfScalarPos(u8, html, i, '>') orelse html.len,
        '&' => for ([_][2][]const u8{ .{ "&amp;", "&" }, .{ "&lt;", "<" }, .{ "&gt;", ">" }, .{ "&quot;", "\"" } }) |e| {
            if (std.mem.startsWith(u8, html[i..], e[0])) {
                try out.appendSlice(arena, e[1]);
                i += e[0].len - 1;
                break;
            }
        } else try out.append(arena, '&'),
        else => |c| try out.append(arena, c),
    };
    return out.items;
}

test render {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const doc = try render(arena.allocator(),
        \\# Intro
        \\Hello *world* & **friends**[^1] with `a<b` and [a link](https://x.y "t").
        \\
        \\- one
        \\- two_three
        \\
        \\```zig
        \\const x = 1 < 2;
        \\```
        \\
        \\[^1]: A _side_ note.
    );
    try std.testing.expectEqualStrings(
        \\<h2 id="intro">Intro</h2>
        \\<p>Hello <em>world</em> &amp; <strong>friends</strong><label for="sn-1" class="margin-toggle sidenote-number"></label><input type="checkbox" id="sn-1" class="margin-toggle"/><span class="sidenote">A <em>side</em> note.</span> with <code>a&lt;b</code> and <a href="https://x.y">a link</a>.</p>
        \\<ul>
        \\<li>one</li>
        \\<li>two_three</li>
        \\</ul>
        \\<pre><code class="language-zig">const x = 1 &lt; 2;
        \\</code></pre>
        \\
    , doc.html);
    try std.testing.expectEqualStrings("Hello world & friends with a<b and a link.", doc.excerpt);
}
