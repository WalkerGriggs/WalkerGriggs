//! Static site generator for walkergriggs.com: a directory of Markdown + YAML front matter → `public/`.
//! Usage: `zig build run -- <content-dir> <out-dir>`
const std = @import("std");
const md = @import("markdown.zig");
const Io = std.Io;
const attr = md.attr;

const site = .{
    .url = "https://walkergriggs.com",
    .title = "Walker Griggs",
    .description = "Walker Griggs is a distributed systems engineer, focused on developer-first platforms, based in San Francisco.",
    .email = "hello@walkergriggs.com",
    .twitter = "@WalkerGriggs",
    .same_as = [_][]const u8{ "https://github.com/WalkerGriggs", "https://x.com/WalkerGriggs" },
};
/// All CSS is inlined: no render-blocking requests and no web fonts (system serif).
const css = @embedFile("vendor/tufte.css") ++ @embedFile("vendor/daisyui.css") ++ @embedFile("site.css");
/// Front matter `categories` → the label shown in the post list.
const labels = std.StaticStringMap([]const u8).initComptime(.{ .{ "essays", "essay" }, .{ "talks", "talk" }, .{ "recently", "micro" } });

const Page = struct {
    title: []const u8,
    url: []const u8, // site-relative: `/2024/10/16/slug/`, `/about/`, `/404.html`
    description: []const u8 = site.description,
    date: []const u8 = "", // ISO 8601; dated pages are listed under Writing
    category: []const u8 = "",
    lastmod: []const u8 = "",
    image: []const u8 = "",
    html: []const u8 = "",
    noindex: bool = false,
};

const Gen = struct {
    arena: std.mem.Allocator,
    io: Io,
    out: Io.Dir,
    year: u16,
    indexed: std.ArrayList(Page) = .empty,

    fn write(g: *Gen, path: []const u8, data: []const u8) !void {
        if (std.fs.path.dirname(path)) |d| try g.out.createDirPath(g.io, d);
        try g.out.writeFile(g.io, .{ .sub_path = path, .data = data });
    }

    /// Wraps `body` in the shared layout and writes it to the file for `p.url`.
    fn page(g: *Gen, p: Page, body: []const u8) !void {
        var buf: Io.Writer.Allocating = .init(g.arena);
        const w = &buf.writer;
        const home = std.mem.eql(u8, p.url, "/");
        const post = p.date.len >= 10;
        const abs = try std.fmt.allocPrint(g.arena, "{s}{s}", .{ site.url, p.url });
        const title = if (home) site.title else try std.fmt.allocPrint(g.arena, "{s} · {s}", .{ p.title, site.title });
        try w.print(
            \\<!doctype html>
            \\<html lang="en">
            \\<head>
            \\<meta charset="utf-8">
            \\<meta name="viewport" content="width=device-width, initial-scale=1">
            \\<title>{f}</title>
            \\<meta name="description" content="{f}">
            \\<meta name="author" content="{s}">
            \\<link rel="canonical" href="{f}">
            \\<link rel="alternate" type="application/atom+xml" title="{s}" href="/index.xml">
            \\<link rel="icon" href="/favicon.ico" sizes="any">
            \\<link rel="icon" type="image/webp" sizes="32x32" href="/favicon-32x32.webp">
            \\<link rel="apple-touch-icon" sizes="180x180" href="/apple-touch-icon.webp">
            \\<link rel="manifest" href="/site.webmanifest">
            \\<meta property="og:site_name" content="{s}">
            \\<meta property="og:locale" content="en_US">
            \\<meta property="og:type" content="{s}">
            \\<meta property="og:title" content="{f}">
            \\<meta property="og:description" content="{f}">
            \\<meta property="og:url" content="{f}">
            \\<meta name="twitter:card" content="{s}">
            \\<meta name="twitter:site" content="{s}">
            \\
        , .{ attr(title), attr(p.description), site.title, attr(abs), site.title, site.title, if (post) "article" else "website", attr(p.title), attr(p.description), attr(abs), if (p.image.len > 0) "summary_large_image" else "summary", site.twitter });
        if (p.image.len > 0) try w.print("<meta property=\"og:image\" content=\"{s}{f}\">\n", .{ if (p.image[0] == '/') site.url else "", attr(p.image) });
        if (p.category.len > 0) try w.print("<meta property=\"article:section\" content=\"{f}\">\n", .{attr(p.category)});
        if (post) try w.print("<meta property=\"article:published_time\" content=\"{f}\">\n<meta property=\"article:modified_time\" content=\"{f}\">\n", .{ attr(p.date), attr(p.lastmod) });
        if (p.noindex) try w.writeAll("<meta name=\"robots\" content=\"noindex\">\n");
        try w.print("<script type=\"application/ld+json\">{f}</script>\n", .{std.json.fmt(.{
            .@"@context" = "https://schema.org",
            .@"@type" = if (post) "BlogPosting" else "WebSite",
            .headline = p.title,
            .description = p.description,
            .url = abs,
            .datePublished = @as(?[]const u8, if (post) p.date else null),
            .dateModified = @as(?[]const u8, if (post) p.lastmod else null),
            .author = .{ .@"@type" = "Person", .name = site.title, .url = site.url, .sameAs = site.same_as },
        }, .{ .emit_null_optional_fields = false })});
        try w.print(
            \\<style>{s}</style>
            \\</head>
            \\<body>
            \\<header class="navbar"><a href="/"><img class="logo" src="/apple-touch-icon.webp" alt="{s}" width="38" height="38"></a>
            \\<nav aria-label="Main"><ul><li><a href="/">Home.</a></li><li><a href="/posts/">Writing.</a></li><li><a href="/index.xml">Feed.</a></li></ul></nav></header>
            \\<main>
            \\{s}</main>
            \\<footer class="footer"><p>{d}, <a href="mailto:{s}">{s}</a></p></footer>
            \\</body>
            \\</html>
            \\
        , .{ css, site.title, body, g.year, site.email, site.email });
        if (!p.noindex) try g.indexed.append(g.arena, p);
        const path = if (std.mem.endsWith(u8, p.url, "/")) try std.fmt.allocPrint(g.arena, "{s}index.html", .{p.url[1..]}) else p.url[1..];
        try g.write(path, buf.written());
    }
};

test {
    _ = md;
}

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const io = init.io;
    const args = try init.minimal.args.toSlice(arena);
    if (args.len != 3) {
        std.log.err("usage: {s} <content-dir> <out-dir>", .{args[0]});
        return error.Usage;
    }
    var src = try Io.Dir.cwd().openDir(io, args[1], .{ .iterate = true });
    defer src.close(io);
    const now: std.time.epoch.EpochSeconds = .{ .secs = @intCast(@divFloor(Io.Clock.real.now(io).nanoseconds, std.time.ns_per_s)) };
    var g: Gen = .{ .arena = arena, .io = io, .out = try Io.Dir.cwd().createDirPathOpen(io, args[2], .{}), .year = now.getEpochDay().calculateYearDay().year };
    defer g.out.close(io);

    // Markdown becomes pages; everything else (images, favicons, …) is copied as-is.
    var pages: std.ArrayList(Page) = .empty;
    var walker = try src.walk(arena);
    while (try walker.next(io)) |e| {
        if (e.kind != .file) continue;
        const key = try arena.dupe(u8, e.path);
        const data = try src.readFileAlloc(io, key, arena, .unlimited);
        if (!std.mem.endsWith(u8, key, ".md")) try g.write(key, data) else if (try parse(arena, key, data)) |p| try pages.append(arena, p);
    }
    std.mem.sort(Page, pages.items, {}, struct {
        fn newer(_: void, a: Page, b: Page) bool {
            return std.mem.order(u8, a.date, b.date) == .gt;
        }
    }.newer);

    // Pages; `_index.md` (URL `/`) is the home page's body.
    var posts: std.ArrayList(Page) = .empty;
    for (pages.items) |p| {
        var buf: Io.Writer.Allocating = .init(arena);
        const w = &buf.writer;
        if (std.mem.eql(u8, p.url, "/")) {
            try g.page(p, try std.fmt.allocPrint(arena, "<article>\n<section class=\"content\">\n{s}</section>\n</article>\n", .{p.html}));
            continue;
        }
        try w.print("<article>\n<header class=\"post-header\">\n<h1 class=\"hero\">{f}</h1>\n", .{attr(p.title)});
        if (p.date.len >= 10) try w.print("<time class=\"date\" datetime=\"{f}\">{s}/{s}/{s}</time>\n", .{ attr(p.date), p.date[0..4], p.date[5..7], p.date[8..10] });
        try w.print("</header>\n<section class=\"content\">\n{s}</section>\n</article>\n", .{p.html});
        try g.page(p, buf.written());
        if (p.date.len >= 10) try posts.append(arena, p);
    }

    // Writing: every dated page, newest first, labelled by category.
    var list: Io.Writer.Allocating = .init(arena);
    try list.writer.writeAll("<article>\n<h1 class=\"hero\">Posts</h1>\n<section class=\"content\">\n<ul class=\"page-list\">\n");
    for (posts.items) |p| try list.writer.print("<li><em class=\"label\">{f}</em><a href=\"{f}\">{f}</a><time class=\"date\" datetime=\"{f}\">{s}/{s}/{s}</time></li>\n", .{
        attr(labels.get(p.category) orelse p.category), attr(p.url), attr(p.title), attr(p.date), p.date[0..4], p.date[5..7], p.date[8..10],
    });
    try list.writer.writeAll("</ul>\n</section>\n</article>\n");
    try g.page(.{ .title = "Posts", .url = "/posts/", .description = "Essays, talks, and notes by " ++ site.title ++ "." }, list.written());
    try g.page(.{ .title = "Page not found", .url = "/404.html", .noindex = true }, "<article>\n<h1>Page not found</h1>\n<section>\n<p>That page doesn’t exist. Try <a href=\"/posts/\">Writing</a>.</p>\n</section>\n</article>\n");

    // Atom feed at Hugo's `/index.xml`, plus sitemap and robots.txt.
    var feed: Io.Writer.Allocating = .init(arena);
    try feed.writer.print(
        \\<?xml version="1.0" encoding="utf-8"?>
        \\<feed xmlns="http://www.w3.org/2005/Atom">
        \\<title>{s}</title><subtitle>{s}</subtitle><id>{s}/</id><link href="{s}/"/><link rel="self" href="{s}/index.xml"/>
        \\<author><name>{s}</name></author><updated>{s}</updated>
        \\
    , .{ site.title, site.description, site.url, site.url, site.url, site.title, try rfc3339(arena, if (posts.items.len > 0) posts.items[0].lastmod else "1970-01-01") });
    for (posts.items[0..@min(posts.items.len, 20)]) |p| try feed.writer.print(
        \\<entry><title>{f}</title><link href="{s}{f}"/><id>{s}{f}</id><published>{s}</published><updated>{s}</updated>
        \\<summary>{f}</summary><content type="html">{f}</content></entry>
        \\
    , .{ attr(p.title), site.url, attr(p.url), site.url, attr(p.url), try rfc3339(arena, p.date), try rfc3339(arena, p.lastmod), attr(p.description), attr(p.html) });
    try feed.writer.writeAll("</feed>\n");
    try g.write("index.xml", feed.written());

    var map: Io.Writer.Allocating = .init(arena);
    try map.writer.writeAll("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<urlset xmlns=\"http://www.sitemaps.org/schemas/sitemap/0.9\">\n");
    for (g.indexed.items) |p| {
        try map.writer.print("<url><loc>{s}{f}</loc>", .{ site.url, attr(p.url) });
        if (p.lastmod.len >= 10) try map.writer.print("<lastmod>{s}</lastmod>", .{p.lastmod[0..10]});
        try map.writer.writeAll("</url>\n");
    }
    try map.writer.writeAll("</urlset>\n");
    try g.write("sitemap.xml", map.written());
    try g.write("robots.txt", "User-agent: *\nAllow: /\nSitemap: " ++ site.url ++ "/sitemap.xml\n");
}

/// Front matter (`---` with one `key: value` per line) + Markdown → Page.
/// Returns null for drafts.
fn parse(arena: std.mem.Allocator, key: []const u8, src: []const u8) !?Page {
    var meta: std.StringHashMapUnmanaged([]const u8) = .empty;
    var body = src;
    if (std.mem.startsWith(u8, src, "---")) if (std.mem.indexOf(u8, src[3..], "\n---")) |end| {
        body = src[3 + end + 4 ..];
        var lines = std.mem.splitScalar(u8, src[3 .. 3 + end], '\n');
        while (lines.next()) |line| if (std.mem.indexOfScalar(u8, line, ':')) |c|
            try meta.put(arena, std.mem.trim(u8, line[0..c], " "), std.mem.trim(u8, line[c + 1 ..], " \t\r\"'"));
    };
    if (std.mem.eql(u8, meta.get("draft") orelse "", "true")) return null;
    var categories = std.mem.tokenizeAny(u8, meta.get("categories") orelse "", "[], \"'");

    // URL: front matter `url`, else `/YYYY/MM/DD/<slug or file name>/` for dated files in `posts/`, else the content path.
    const stem = std.fs.path.stem(key);
    const base = if (std.mem.eql(u8, stem, "index") or std.mem.eql(u8, stem, "_index")) std.fs.path.dirname(key) orelse "" else key[0 .. key.len - 3];
    const date = meta.get("date") orelse "";
    var url = if (meta.get("url")) |u|
        try std.fmt.allocPrint(arena, "{s}{s}", .{ if (std.mem.startsWith(u8, u, "/")) "" else "/", u })
    else if (date.len >= 10 and std.mem.startsWith(u8, key, "posts/"))
        try std.fmt.allocPrint(arena, "/{s}/{s}/{s}/{s}/", .{ date[0..4], date[5..7], date[8..10], meta.get("slug") orelse std.fs.path.basename(base) })
    else if (base.len == 0) "/" else try std.fmt.allocPrint(arena, "/{s}/", .{base});
    if (!std.mem.endsWith(u8, url, "/") and std.fs.path.extension(url).len == 0) url = try std.fmt.allocPrint(arena, "{s}/", .{url});
    return .{
        .title = meta.get("title") orelse stem,
        .url = url,
        .description = meta.get("description") orelse site.description,
        .date = date,
        .category = categories.next() orelse "",
        .lastmod = meta.get("lastmod") orelse date,
        .image = meta.get("image") orelse "",
        .html = try md.render(arena, body),
    };
}

fn rfc3339(arena: std.mem.Allocator, date: []const u8) ![]const u8 {
    return if (date.len == 10) std.fmt.allocPrint(arena, "{s}T00:00:00Z", .{date}) else date;
}
