//! Markdown → HTML via md4c (CommonMark + tables, strikethrough, task lists, URL autolinks),
//! with footnotes turned into Tufte sidenotes (`[^mn…]` → margin notes).
const std = @import("std");
const Writer = std.Io.Writer;

pub const Doc = struct { html: []const u8, excerpt: []const u8 };

const md_flags = 0x100 | 0x200 | 0x800 | 0x4; // MD_FLAG_TABLES | STRIKETHROUGH | TASKLISTS | PERMISSIVEURLAUTOLINKS
extern fn md_html(input: [*]const u8, size: c_uint, out: *const fn ([*]const u8, c_uint, ?*anyopaque) callconv(.c) void, userdata: ?*anyopaque, parser_flags: c_uint, renderer_flags: c_uint) c_int;

const Sink = struct {
    out: Writer.Allocating,
    failed: bool = false,
    fn write(text_: [*]const u8, size: c_uint, userdata: ?*anyopaque) callconv(.c) void {
        const s: *Sink = @ptrCast(@alignCast(userdata));
        s.out.writer.writeAll(text_[0..size]) catch {
            s.failed = true;
        };
    }
};

pub fn render(arena: std.mem.Allocator, src: []const u8) !Doc {
    // Footnote definitions (`[^id]: text`, one line each) are lifted out; references become
    // Tufte sidenote markup with the note's Markdown inside, which md4c then renders inline.
    var notes: std.StringHashMapUnmanaged([]const u8) = .empty;
    var lines = std.mem.splitScalar(u8, src, '\n');
    while (lines.next()) |line| if (std.mem.startsWith(u8, line, "[^")) if (std.mem.indexOf(u8, line, "]:")) |e|
        try notes.put(arena, line[2..e], std.mem.trim(u8, line[e + 2 ..], " \t\r"));

    var md: Writer.Allocating = .init(arena);
    var fenced = false;
    var count: usize = 0;
    lines.reset();
    while (lines.next()) |line| {
        if (std.mem.startsWith(u8, std.mem.trimStart(u8, line, " "), "```")) fenced = !fenced;
        if (!fenced and std.mem.startsWith(u8, line, "[^") and std.mem.indexOf(u8, line, "]:") != null) continue;
        var rest = line;
        while (if (fenced) null else std.mem.indexOf(u8, rest, "[^")) |at| {
            const end = std.mem.indexOfScalarPos(u8, rest, at, ']') orelse break;
            const id = rest[at + 2 .. end];
            const note = notes.get(id) orelse break;
            const margin = std.mem.startsWith(u8, id, "mn");
            count += 1;
            try md.writer.print("{s}<label for=\"sn-{d}\" class=\"margin-toggle{s}\">{s}</label><input type=\"checkbox\" id=\"sn-{d}\" class=\"margin-toggle\"/><span class=\"{s}\">{s}</span>", .{
                rest[0..at], count, if (margin) "" else " sidenote-number", if (margin) "&#8853;" else "", count, if (margin) "marginnote" else "sidenote", note,
            });
            rest = rest[end + 1 ..];
        }
        try md.writer.print("{s}\n", .{rest});
    }

    var sink: Sink = .{ .out = .init(arena) };
    if (md_html(md.written().ptr, @intCast(md.written().len), Sink.write, &sink, md_flags, 0) != 0 or sink.failed) return error.MarkdownFailed;

    // Demote `#` to <h2> (the page title is the only <h1>), give headings anchor ids, lazy-load images.
    const raw = try std.mem.replaceOwned(u8, arena, sink.out.written(), "<img ", "<img loading=\"lazy\" ");
    var html: Writer.Allocating = .init(arena);
    var ids: std.StringHashMapUnmanaged(usize) = .empty;
    var i: usize = 0;
    while (std.mem.indexOfPos(u8, raw, i, "<h")) |at| {
        const end = std.mem.indexOfPos(u8, raw, at, "</h") orelse break;
        if (at + 3 >= raw.len or raw[at + 3] != '>' or raw[at + 2] < '1' or raw[at + 2] > '6') {
            try html.writer.writeAll(raw[i .. at + 2]);
            i = at + 2;
            continue;
        }
        const level = @max(raw[at + 2] - '0', 2);
        const id = try slug(arena, try text(arena, raw[at + 4 .. end]));
        const seen = try ids.getOrPutValue(arena, id, 0);
        seen.value_ptr.* += 1;
        try html.writer.print("{s}<h{d} id=\"{s}", .{ raw[i..at], level, id });
        if (seen.value_ptr.* > 1) try html.writer.print("-{d}", .{seen.value_ptr.*});
        try html.writer.print("\">{s}</h{d}>", .{ raw[at + 4 .. end], level });
        i = end + 5;
    }
    try html.writer.writeAll(raw[i..]);
    return .{ .html = html.written(), .excerpt = try excerpt(arena, html.written()) };
}

/// Plain text of the first paragraph, without sidenotes.
fn excerpt(arena: std.mem.Allocator, html: []const u8) ![]const u8 {
    const start = (std.mem.indexOf(u8, html, "<p>") orelse return "") + 3;
    var p = html[start .. std.mem.indexOfPos(u8, html, start, "</p>") orelse html.len];
    while (std.mem.indexOf(u8, p, "<label for=\"sn-")) |a| {
        const b = (std.mem.indexOfPos(u8, p, a, "</span>") orelse break) + "</span>".len;
        p = try std.mem.concat(arena, u8, &.{ p[0..a], p[b..] });
    }
    return text(arena, p);
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
        '&' => for ([_][2][]const u8{ .{ "&amp;", "&" }, .{ "&lt;", "<" }, .{ "&gt;", ">" }, .{ "&quot;", "\"" }, .{ "&#x27;", "'" } }) |e| {
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
        \\## Intro
        \\
        \\```zig
        \\const x = 1 < 2; // [^1]
        \\```
        \\
        \\[^1]: A _side_ note.
    );
    try std.testing.expectEqualStrings(
        \\<h2 id="intro">Intro</h2>
        \\<p>Hello <em>world</em> &amp; <strong>friends</strong><label for="sn-1" class="margin-toggle sidenote-number"></label><input type="checkbox" id="sn-1" class="margin-toggle"/><span class="sidenote">A <em>side</em> note.</span> with <code>a&lt;b</code> and <a href="https://x.y" title="t">a link</a>.</p>
        \\<ul>
        \\<li>one</li>
        \\<li>two_three</li>
        \\</ul>
        \\<h2 id="intro-2">Intro</h2>
        \\<pre><code class="language-zig">const x = 1 &lt; 2; // [^1]
        \\</code></pre>
        \\
    , doc.html);
    try std.testing.expectEqualStrings("Hello world & friends with a<b and a link.", doc.excerpt);
}
