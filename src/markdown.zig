//! Markdown → HTML via md4c (CommonMark + tables, strikethrough, task lists, URL autolinks),
//! with footnotes turned into Tufte sidenotes (`[^mn…]` → margin notes).
const std = @import("std");
const Writer = std.Io.Writer;

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

pub fn render(arena: std.mem.Allocator, src: []const u8) ![]const u8 {
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
    return std.mem.replaceOwned(u8, arena, sink.out.written(), "<img ", "<img loading=\"lazy\" ");
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

test render {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const html = try render(arena.allocator(),
        \\## Intro
        \\Hello *world* & **friends**[^1] with `a<b` and [a link](https://x.y "t").
        \\
        \\- one
        \\- two_three
        \\
        \\![alt](/a.png)
        \\
        \\```zig
        \\const x = 1 < 2; // [^1]
        \\```
        \\
        \\[^1]: A _side_ note.
    );
    try std.testing.expectEqualStrings(
        \\<h2>Intro</h2>
        \\<p>Hello <em>world</em> &amp; <strong>friends</strong><label for="sn-1" class="margin-toggle sidenote-number"></label><input type="checkbox" id="sn-1" class="margin-toggle"/><span class="sidenote">A <em>side</em> note.</span> with <code>a&lt;b</code> and <a href="https://x.y" title="t">a link</a>.</p>
        \\<ul>
        \\<li>one</li>
        \\<li>two_three</li>
        \\</ul>
        \\<p><img loading="lazy" src="/a.png" alt="alt"></p>
        \\<pre><code class="language-zig">const x = 1 &lt; 2; // [^1]
        \\</code></pre>
        \\
    , html);
}
