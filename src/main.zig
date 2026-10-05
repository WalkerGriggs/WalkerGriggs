//! Static site generator for walkergriggs.com: a directory of Markdown + YAML front matter → `public/`.
//! Usage: `zig build run -- <content-dir>`
const std = @import("std");
const md = @import("markdown.zig");
const Io = std.Io;
const attr = md.attr;

const site = .{
    .url = "https://walkergriggs.com",
    .title = "Walker Griggs",
    .description = "Writing on software, video, and systems by Walker Griggs.",
    .twitter = "@WalkerGriggs",
    .same_as = [_][]const u8{ "https://github.com/WalkerGriggs", "https://x.com/WalkerGriggs" },
};
const months = [_][]const u8{ "January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December" };

const Page = struct {
    title: []const u8,
    url: []const u8, // site-relative: `/2024/10/16/slug/`, `/about/`, `/404.html`
    description: []const u8 = site.description,
    date: []const u8 = "", // ISO 8601; dated pages are posts
    lastmod: []const u8 = "",
    image: []const u8 = "",
    tags: []const []const u8 = &.{},
    html: []const u8 = "",
    noindex: bool = false,
};

const Gen = struct {
    arena: std.mem.Allocator,
    io: Io,
    out: Io.Dir,
    nav: []const Page,
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
            \\<meta property="og:site_name" content="{s}">
            \\<meta property="og:type" content="{s}">
            \\<meta property="og:title" content="{f}">
            \\<meta property="og:description" content="{f}">
            \\<meta property="og:url" content="{f}">
            \\<meta name="twitter:card" content="{s}">
            \\<meta name="twitter:site" content="{s}">
            \\
        , .{ attr(title), attr(p.description), site.title, attr(abs), site.title, site.title, if (post) "article" else "website", attr(p.title), attr(p.description), attr(abs), if (p.image.len > 0) "summary_large_image" else "summary", site.twitter });
        if (p.image.len > 0) try w.print("<meta property=\"og:image\" content=\"{s}{f}\">\n", .{ if (p.image[0] == '/') site.url else "", attr(p.image) });
        if (post) try w.print("<meta property=\"article:published_time\" content=\"{f}\">\n<meta property=\"article:modified_time\" content=\"{f}\">\n", .{ attr(p.date), attr(p.lastmod) });
        for (p.tags) |t| try w.print("<meta property=\"article:tag\" content=\"{f}\">\n", .{attr(t)});
        if (p.noindex) try w.writeAll("<meta name=\"robots\" content=\"noindex\">\n");
        try w.print("<script type=\"application/ld+json\">{f}</script>\n", .{std.json.fmt(.{
            .@"@context" = "https://schema.org",
            .@"@type" = if (post) "BlogPosting" else "WebSite",
            .headline = p.title,
            .description = p.description,
            .url = abs,
            .datePublished = @as(?[]const u8, if (post) p.date else null),
            .dateModified = @as(?[]const u8, if (post) p.lastmod else null),
            .keywords = p.tags,
            .author = .{ .@"@type" = "Person", .name = site.title, .url = site.url, .sameAs = site.same_as },
        }, .{ .emit_null_optional_fields = false })});
        try w.print(
            \\<link rel="preconnect" href="https://cdn.jsdelivr.net" crossorigin>
            \\<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/tufte-css@1.9.0/tufte.min.css" integrity="sha384-Unq5KW28ad1eDFy7/pDgACNgonWWhdG3sAtKrqnhYJKZQ0whjkfn59wmTUNGGtF0" crossorigin="anonymous">
            \\<link rel="stylesheet" href="https://cdn.jsdelivr.net/combine/npm/daisyui@5.7.47/theme/light.css,npm/daisyui@5.7.47/components/navbar.css,npm/daisyui@5.7.47/components/badge.css,npm/daisyui@5.7.47/components/footer.css">
            \\<style>{s}</style>
            \\</head>
            \\<body>
            \\<header class="navbar"><a class="site-title" href="/">{s}</a><nav aria-label="Main">
        , .{ @embedFile("site.css"), site.title });
        for (g.nav) |n| try w.print("<a href=\"{f}\">{f}</a>", .{ attr(n.url), attr(n.title) });
        try w.print(
            \\<a href="/tags/">Tags</a></nav></header>
            \\<main>
            \\{s}</main>
            \\<footer class="footer"><p>© {s} · <a rel="me" href="{s}">GitHub</a> · <a rel="me" href="{s}">X</a> · <a href="/index.xml">Feed</a></p></footer>
            \\</body>
            \\</html>
            \\
        , .{ body, site.title, site.same_as[0], site.same_as[1] });
        if (!p.noindex) try g.indexed.append(g.arena, p);
        const path = if (std.mem.endsWith(u8, p.url, "/")) try std.fmt.allocPrint(g.arena, "{s}index.html", .{p.url[1..]}) else p.url[1..];
        try g.write(path, buf.written());
    }

    /// A titled archive of posts grouped by year (home and tag pages).
    fn archive(g: *Gen, p: Page, intro: []const u8, posts: []const Page) !void {
        var buf: Io.Writer.Allocating = .init(g.arena);
        const w = &buf.writer;
        try w.print("<article>\n<h1>{f}</h1>\n<section>\n{s}", .{ attr(p.title), intro });
        var year: []const u8 = "";
        for (posts) |post| {
            if (!std.mem.eql(u8, year, post.date[0..4])) {
                if (year.len > 0) try w.writeAll("</ul>\n");
                year = post.date[0..4];
                try w.print("<h2>{s}</h2>\n<ul class=\"posts\">\n", .{year});
            }
            try w.print("<li><a href=\"{f}\">{f}</a> <time datetime=\"{f}\">{s}</time></li>\n", .{ attr(post.url), attr(post.title), attr(post.date), try human(g.arena, post.date) });
        }
        try w.writeAll(if (year.len > 0) "</ul>\n</section>\n</article>\n" else "</section>\n</article>\n");
        try g.page(p, buf.written());
    }
};

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
    var g: Gen = .{ .arena = arena, .io = io, .out = try Io.Dir.cwd().createDirPathOpen(io, args[2], .{}), .nav = &.{} };
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
            return std.mem.order(u8, a.date, b.date) == .gt or (a.date.len == 0 and b.date.len == 0 and std.mem.order(u8, a.url, b.url) == .lt);
        }
    }.newer);

    // Dated pages are posts; undated pages (other than the home intro) form the navigation.
    var posts: std.ArrayList(Page) = .empty;
    var nav: std.ArrayList(Page) = .empty;
    var home: Page = .{ .title = site.title, .url = "/" };
    var tags: std.StringArrayHashMapUnmanaged(std.ArrayList(Page)) = .empty;
    for (pages.items) |p| {
        if (std.mem.eql(u8, p.url, "/")) {
            home = .{ .title = site.title, .url = "/", .description = p.description, .html = p.html };
        } else if (p.date.len >= 10) {
            try posts.append(arena, p);
            for (p.tags) |t| {
                const entry = try tags.getOrPutValue(arena, t, .empty);
                try entry.value_ptr.append(arena, p);
            }
        } else try nav.append(arena, p);
    }
    g.nav = nav.items;

    for (pages.items) |p| if (!std.mem.eql(u8, p.url, "/")) {
        var buf: Io.Writer.Allocating = .init(arena);
        const w = &buf.writer;
        try w.print("<article>\n<h1>{f}</h1>\n", .{attr(p.title)});
        if (p.date.len >= 10) try w.print("<p class=\"subtitle\"><time datetime=\"{f}\">{s}</time></p>\n", .{ attr(p.date), try human(arena, p.date) });
        try w.print("<section>\n{s}</section>\n", .{p.html});
        if (p.tags.len > 0) try w.writeAll("<footer class=\"tags\">");
        for (p.tags) |t| try w.print("<a class=\"badge badge-outline\" rel=\"tag\" href=\"/tags/{s}/\">{f}</a>", .{ try md.slug(arena, t), attr(t) });
        try w.writeAll(if (p.tags.len > 0) "</footer>\n</article>\n" else "</article>\n");
        try g.page(p, buf.written());
    };
    try g.archive(home, home.html, posts.items);

    var tag_index: Io.Writer.Allocating = .init(arena);
    try tag_index.writer.writeAll("<ul class=\"posts\">\n");
    for (tags.keys(), tags.values()) |t, list| {
        const url = try std.fmt.allocPrint(arena, "/tags/{s}/", .{try md.slug(arena, t)});
        const desc = try std.fmt.allocPrint(arena, "Posts tagged “{s}” by {s}.", .{ t, site.title });
        try g.archive(.{ .title = try std.fmt.allocPrint(arena, "Tagged “{s}”", .{t}), .url = url, .description = desc }, "", list.items);
        try tag_index.writer.print("<li><a href=\"{s}\">{f}</a> <span>{d}</span></li>\n", .{ url, attr(t), list.items.len });
    }
    try tag_index.writer.writeAll("</ul>\n");
    try g.archive(.{ .title = "Tags", .url = "/tags/", .description = "Every topic on " ++ site.title ++ "." }, tag_index.written(), &.{});
    try g.page(.{ .title = "Page not found", .url = "/404.html", .noindex = true }, "<article>\n<h1>Page not found</h1>\n<section>\n<p>That page doesn’t exist. Try the <a href=\"/\">archive</a>.</p>\n</section>\n</article>\n");

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

/// Front matter (`---` YAML subset: `key: value`, `[a, b]` and `- item` lists) + Markdown → Page.
/// Returns null for drafts.
fn parse(arena: std.mem.Allocator, key: []const u8, src: []const u8) !?Page {
    var meta: std.StringHashMapUnmanaged([]const u8) = .empty;
    var body = src;
    if (std.mem.startsWith(u8, src, "---")) if (std.mem.indexOf(u8, src[3..], "\n---")) |end| {
        body = src[3 + end + 4 ..];
        var last: []const u8 = "";
        var lines = std.mem.splitScalar(u8, src[3 .. 3 + end], '\n');
        while (lines.next()) |raw| {
            const line = std.mem.trimEnd(u8, raw, " \r");
            const t = std.mem.trim(u8, line, " ");
            if (std.mem.startsWith(u8, t, "- ")) { // a list item continues the previous key
                const prev = meta.get(last) orelse "";
                try meta.put(arena, last, try std.fmt.allocPrint(arena, "{s}{s}{s}", .{ prev, if (prev.len > 0) "," else "", t[2..] }));
            } else if (std.mem.indexOfScalar(u8, line, ':')) |c| {
                last = std.mem.trim(u8, line[0..c], " ");
                try meta.put(arena, last, unquote(line[c + 1 ..]));
            }
        }
    };
    if (std.mem.eql(u8, meta.get("draft") orelse "", "true")) return null;

    // URL: front matter `url`, else `/YYYY/MM/DD/<slug or file name>/` for posts, else the content path.
    const stem = std.fs.path.stem(key);
    const base = if (std.mem.eql(u8, stem, "index") or std.mem.eql(u8, stem, "_index")) std.fs.path.dirname(key) orelse "" else key[0 .. key.len - 3];
    const date = meta.get("date") orelse "";
    var url = if (meta.get("url")) |u|
        try std.fmt.allocPrint(arena, "{s}{s}", .{ if (std.mem.startsWith(u8, u, "/")) "" else "/", u })
    else if (date.len >= 10)
        try std.fmt.allocPrint(arena, "/{s}/{s}/{s}/{s}/", .{ date[0..4], date[5..7], date[8..10], meta.get("slug") orelse std.fs.path.basename(base) })
    else if (base.len == 0) "/" else try std.fmt.allocPrint(arena, "/{s}/", .{base});
    if (!std.mem.endsWith(u8, url, "/") and std.fs.path.extension(url).len == 0) url = try std.fmt.allocPrint(arena, "{s}/", .{url});

    var tags: std.ArrayList([]const u8) = .empty;
    var it = std.mem.tokenizeAny(u8, meta.get("tags") orelse "", "[],");
    while (it.next()) |t| if (unquote(t).len > 0) try tags.append(arena, unquote(t));

    const doc = try md.render(arena, body);
    const summary = if (doc.excerpt.len <= 160) doc.excerpt else try std.fmt.allocPrint(arena, "{s}…", .{doc.excerpt[0 .. std.mem.lastIndexOfScalar(u8, doc.excerpt[0..157], ' ') orelse 157]});
    return .{
        .title = meta.get("title") orelse stem,
        .url = url,
        .description = meta.get("description") orelse meta.get("summary") orelse if (summary.len > 0) summary else site.description,
        .date = date,
        .lastmod = meta.get("lastmod") orelse date,
        .image = meta.get("image") orelse "",
        .tags = tags.items,
        .html = doc.html,
    };
}

fn unquote(s: []const u8) []const u8 {
    return std.mem.trim(u8, s, " \t\"'");
}

/// `2024-10-16…` → `October 16, 2024`.
fn human(arena: std.mem.Allocator, date: []const u8) ![]const u8 {
    const m = std.fmt.parseInt(u8, date[5..7], 10) catch 1;
    const d = std.fmt.parseInt(u8, date[8..10], 10) catch 1;
    return std.fmt.allocPrint(arena, "{s} {d}, {s}", .{ months[@min(m, 12) -| 1], d, date[0..4] });
}

fn rfc3339(arena: std.mem.Allocator, date: []const u8) ![]const u8 {
    return if (date.len == 10) std.fmt.allocPrint(arena, "{s}T00:00:00Z", .{date}) else date;
}
