<div align="center">
<img width="1500" height="500" src="https://github.com/user-attachments/assets/300f8fd7-9f6b-4ab5-8eff-c911780e9ee7" />

[![pgp](https://img.shields.io/badge/pgp-3F59872EBAFDD222-000)](https://github.com/walkergriggs.gpg)
[![www](https://img.shields.io/badge/www-walkergriggs.com-000)](https://www.walkergriggs.com)
[![x](https://img.shields.io/badge/x-@WalkerGriggs-000)](https://x.com/WalkerGriggs)

</div>

# walkergriggs.com

A small static site generator, written in Zig, that builds [walkergriggs.com](https://walkergriggs.com) from a directory of Markdown files.

- **Small.** About 590 lines of Zig. It uses only the standard library, plus ImageMagick for images.
- **Tufte layout.** A main text column with a side column for sidenotes and margin notes. Typography comes from [tufte-css](https://github.com/edwardtufte/tufte-css), and the navbar, badges and footer come from [daisyUI](https://daisyui.com).
- **Light pages.** All CSS is inlined and the site uses system fonts. There are no web fonts, no JavaScript and no third-party requests. The homepage is about 11 KB uncompressed (about 4 KB gzipped). Photos are resized and re-encoded as WebP.
- **SEO built in.** Every page gets a canonical URL, description, Open Graph and Twitter tags, and JSON-LD. The site also gets an Atom feed, `sitemap.xml` and `robots.txt`.
- **Stable URLs.** Posts are published at `/YYYY/MM/DD/<slug>/`, the same paths the site has always used.

## Contents

- [Quick start](#quick-start)
- [Commands](#commands)
- [Project layout](#project-layout)
- [Writing content](#writing-content)
- [Markdown reference](#markdown-reference)
- [What gets generated](#what-gets-generated)
- [SEO](#seo)
- [Styling](#styling)
- [Configuration](#configuration)
- [Deploying](#deploying)
- [Migrating from Hugo](#migrating-from-hugo)
- [Limitations](#limitations)
- [Licenses](#licenses)

## Quick start

You need **Zig 0.16.0** and **ImageMagick** (its `convert` command, built with WebP support). The generator uses Zig's new `std.Io` APIs, so older Zig versions won't compile it.

```sh
# Install Zig, using any one of these:
#   https://ziglang.org/download/      (official tarballs)
#   brew install zig                   (macOS)
#   pip install ziglang==0.16.0        (ships the binary as python -m ziglang)
# Install ImageMagick: brew install imagemagick  |  apt install imagemagick

zig build run                          # content/ → public/
python3 -m http.server -d public 8000  # preview at http://localhost:8000
```

## Commands

| Command | What it does |
| --- | --- |
| `zig build` | Compiles the generator to `zig-out/bin/ssg`. |
| `zig build run` | Builds the site from `content/` into `public/`. |
| `zig build run -- <content-dir> <out-dir>` | Builds from and to any directories. |
| `zig build test` | Runs the unit tests. |
| `zig build -Doptimize=ReleaseFast` | Builds an optimized binary (useful in CI). |
| `zig-out/bin/ssg <content-dir> <out-dir>` | Runs the compiled binary directly. |

The generator overwrites files in the output directory but never deletes any. For a clean build that drops pages you've removed or renamed, delete the output directory first:

```sh
rm -rf public && zig build run
```

## Project layout

```
build.zig            build, run, and test steps
build.zig.zon        package manifest (requires Zig 0.16.0)
src/
  main.zig           reads content, parses front matter, writes pages, feed, sitemap, robots.txt
  markdown.zig       Markdown → HTML, with footnotes turned into Tufte sidenotes
  images.zig         resizes raster images and converts them to WebP with ImageMagick
  site.css           site-specific styles; maps daisyUI's colors onto Tufte's palette
  vendor/
    tufte.css        tufte-css 1.9.0 with the ET Book @font-face rules removed
    daisyui.css      only the daisyUI 5.7.47 rules the site uses
content/             sample content that uses every feature
public/              generated output (git-ignored)
```

## Writing content

The generator walks the content directory recursively:

- Every `.md` file becomes a page.
- **Raster images** (`.png`, `.jpg`, `.jpeg`, `.gif`, `.webp`) are converted before any page is built. See [Images](#images).
- **Every other file is copied as-is** to the same relative path. For example, `content/images/diagram.svg` is published at `/images/diagram.svg`. Put SVGs, favicons, `CNAME` files and similar here. Hidden files such as `.DS_Store` are copied too, so keep the directory clean.

### Images

Each raster image goes through one ImageMagick command:

- It is rotated according to its EXIF orientation, and its metadata (EXIF, GPS, color profiles) is removed.
- It is shrunk to **at most 1350 px wide**, about twice the widest text column, so it stays sharp on high-DPI screens. Smaller images are never enlarged.
- It is encoded as **lossy WebP at quality 80**. Only the first frame of an animated GIF is kept.
- The `.webp` is published next to where the original would be. For example, `content/images/a.jpg` becomes `/images/a.webp`. **The original file is not published.**

Reference images by their **original absolute path**, such as `![Alt text](/images/a.jpg)`. The generator rewrites the reference to the `.webp` and adds `width` and `height`, so the page doesn't shift while the image loads. The `image:` front matter key is rewritten the same way. Raw HTML `<img>` tags and relative paths are *not* rewritten; point those at the `.webp` yourself.

To change the size or quality, edit `max_width` or the `argv` line in `src/images.zig`.

### Front matter

Each Markdown file can start with YAML front matter between `---` lines. Only a subset of YAML is supported: `key: value` pairs, inline lists (`[a, b]`), and `- item` lists.

```markdown
---
title: "PSSH: the primordial soup of secure-ish headers"
date: 2024-10-16
lastmod: 2024-11-02T09:30:00-04:00
description: What's actually inside a PSSH box, and why every DRM system reads it differently.
tags: [video, drm]
image: /images/pssh-card.png
---
Your post starts here.
```

| Key | Default | Purpose |
| --- | --- | --- |
| `title` | file name | Page title, `<h1>`, and the title used in the feed and in social previews. |
| `date` | none | `YYYY-MM-DD` or full ISO 8601. **A page with a date is a post.** Posts get a dated URL and appear on the homepage, in tag pages, and in the feed. |
| `lastmod` | `date` | Last-modified date for the feed, sitemap, and JSON-LD. |
| `description` | `summary`, then the first paragraph | Meta and social description. Write one per post; the fallback is cut at about 160 characters. |
| `summary` | none | Used if `description` is missing. |
| `slug` | file name | The last part of a post's URL. |
| `url` | see below | Sets the page's path exactly. Use it to keep a legacy URL. |
| `tags` | none | Builds tag pages at `/tags/<tag>/` and adds `article:tag` meta tags. |
| `image` | none | Social preview image (`og:image`). Paths starting with `/` are made absolute. |
| `draft` | `false` | `draft: true` skips the file entirely. |

If you write a date with a time, include a timezone (`2024-10-16T09:00:00-04:00`). It is passed to the feed unchanged, and Atom requires one.

### URLs

Each page's path is chosen by the first rule that applies:

1. **`url:` in front matter.** Used exactly as written, with a leading `/` added if it's missing. A path with no file extension gets a trailing slash, so `/about` becomes `/about/` and is written to `about/index.html`. A path with an extension, such as `/feed.html`, is written as that file.
2. **Posts** (pages with a `date`) go to `/YYYY/MM/DD/<slug>/`. The slug is the `slug:` value if set, otherwise the file name. For example, `posts/pipewire_in_docker.md` dated `2022-12-03` goes to `/2022/12/03/pipewire_in_docker/`. The directory a post sits in doesn't affect its URL.
3. **Pages** (no `date`) mirror their path in `content/`. `about.md` goes to `/about/`, and `projects/index.md` goes to `/projects/`.

`index.md` and `_index.md` stand for their directory, as in Hugo. A top-level `_index.md` (URL `/`) is the **homepage intro**: its body is shown above the list of posts.

### Navigation

Every undated page except the homepage appears in the navbar, sorted by URL. A **Tags** link is always added.

## Markdown reference

The renderer supports a deliberately small subset of Markdown. `content/posts/markdown_kitchen_sink.md` uses all of it.

| Syntax | Output |
| --- | --- |
| `# Heading` … `###### Heading` | `<h2>`–`<h6>` with an `id` for anchor links. **`#` becomes `<h2>`**, because the page title is the only `<h1>`. |
| blank-line-separated text | `<p>` |
| `*em*`, `_em_` | `<em>` (an underscore inside a word, as in `snake_case`, is left alone) |
| `**strong**`, `__strong__` | `<strong>` |
| `` `code` `` | `<code>` |
| `[text](https://…)` | link (an optional `"title"` is ignored) |
| `<https://…>` | autolink |
| `![alt](/img.png)` | `<img loading="lazy">`, pointing to the WebP version with `width` and `height`. Always write alt text. |
| `- item`, `* item`, `+ item` | `<ul>` |
| `1. item`, `1) item` | `<ol>` (the numbers you write are ignored) |
| `> quote` | `<blockquote>`; a bare `>` line starts a new paragraph |
| ```` ```lang ```` fences | `<pre><code class="language-lang">`, content escaped |
| `---`, `***`, `___` | `<hr>` |
| a line starting with `<` | raw HTML, passed through until the next blank line |
| inline `<tag>` and `&entity;` | passed through |
| `\*` | a literal character |

### Sidenotes and margin notes

Footnotes become Tufte sidenotes, shown in the side column next to the line that references them. On narrow screens they fold away behind a tap target.

```markdown
A claim that needs a citation.[^1] A thought with no number.[^mn-aside]

[^1]: The citation, with **formatting** and [links](https://example.com).
[^mn-aside]: ![A sparkline](/images/sparkline.svg) Margin notes can hold images too.
```

- Notes are numbered automatically, in the order they appear.
- A note whose id **starts with `mn`** becomes an unnumbered **margin note**, marked ⊕ on mobile.
- The note text must be on a **single line**. It can contain inline formatting, links and images.
- Note definitions can go anywhere in the file; the bottom is conventional.

### Full-width figures and other Tufte features

Use raw HTML for anything tufte-css supports that Markdown doesn't, such as full-width figures, epigraphs and new-thought openings:

```html
<figure class="fullwidth">
  <img src="/images/wide.png" alt="Describe the figure">
</figure>
```

## What gets generated

| Path | Contents |
| --- | --- |
| `/index.html` | The homepage intro, then posts grouped by year, newest first |
| `/YYYY/MM/DD/<slug>/index.html` | Each post |
| `/<page>/index.html` | Each undated page |
| `/<path>.webp` | Each raster image, resized and converted |
| `/tags/index.html` | All tags, with post counts |
| `/tags/<tag>/index.html` | Posts with that tag |
| `/index.xml` | Atom feed of the 20 newest posts, with full content (Hugo's feed path) |
| `/sitemap.xml` | Every indexable page, with `lastmod` |
| `/robots.txt` | Allows all crawlers and points to the sitemap |
| `/404.html` | A "not found" page marked `noindex` |

## SEO

Every page includes:

- A unique `<title>` (`Post title · Walker Griggs`) and a `<meta name="description">`.
- `<link rel="canonical">` with the absolute URL.
- Open Graph (`og:*`) and Twitter Card tags. Posts also get `article:published_time`, `article:modified_time` and `article:tag`.
- JSON-LD: `BlogPosting` for posts and `WebSite` for other pages, with a `Person` author that links to your GitHub and X profiles.
- Semantic HTML: `<article>`, `<section>`, `<time datetime>`, a single `<h1>`, `lang="en"`, heading anchors, and `rel="me"` and `rel="tag"` links.
- A link to the Atom feed.

Because there are no blocking requests, web fonts or scripts, Core Web Vitals scores should be close to the maximum.

## Styling

- **`src/vendor/tufte.css`** provides the typography and grid: a 55% text column, sidenotes floated into the side column, and the mobile toggles. Its ET Book `@font-face` rules were removed, and text uses a system old-style serif instead: Iowan Old Style on Apple devices, Palatino Linotype on Windows, and URW Palladio or P052 on Linux.
- **`src/vendor/daisyui.css`** contains only the daisyUI rules the site uses: the light theme tokens, `navbar`, `badge`, `badge-outline` and `footer`. If you use another daisyUI class, copy its rules in from the `daisyui` npm package (`components/<name>.css`).
- **`src/site.css`** maps daisyUI's colors to Tufte's palette (`#fffff8` and `#111`, or `#151515` and `#ddd` in dark mode) and lays out the navbar, post lists, tags and footer.
- Dark mode follows the operating system setting (`prefers-color-scheme`).

All three files are compiled into the binary with `@embedFile` and inlined into every page. After editing any of them, run `zig build run` again.

## Configuration

Site-wide settings live in the `site` constant at the top of `src/main.zig`:

```zig
const site = .{
    .url = "https://walkergriggs.com",     // canonical origin, without a trailing slash
    .title = "Walker Griggs",
    .description = "…",                    // default meta description
    .twitter = "@WalkerGriggs",
    .same_as = [_][]const u8{ "https://github.com/WalkerGriggs", "https://x.com/WalkerGriggs" },
};
```

## Deploying

`public/` is a plain directory of files, so any static host works: Cloudflare Pages, Netlify, GitHub Pages, S3 with CloudFront, or nginx. A typical CI job:

```sh
rm -rf public
zig build run -Doptimize=ReleaseFast
# upload public/
```

Configure the host to:

- **Return `/404.html` with a 404 status** for missing paths.
- **Redirect `/path` to `/path/`** (301), so every page has one URL.
- **Redirect `www.walkergriggs.com` and `blog.walkergriggs.com`** to the same path on `walkergriggs.com` (301). Older shares of your posts point at the `blog.` subdomain, and redirecting keeps the credit from those links.
- Serve with Brotli or gzip compression. Cache images for a long time; HTML can use a short cache lifetime.

Once the site is live, submit `https://walkergriggs.com/sitemap.xml` in Google Search Console and Bing Webmaster Tools.

## Migrating from Hugo

Most Hugo content works unchanged: YAML front matter, `date`, `slug`, `url`, `tags`, `draft`, `_index.md`, the `/index.xml` feed path and the `/tags/<tag>/` paths are all supported. Differences:

- **Shortcodes are not executed.** They appear as literal text. Convert `sidenote` and `marginnote` shortcodes to footnotes with the script below, then find any others with `grep -rhoE '\{\{[<%] *[a-z]+' content | sort | uniq -c`.
- **TOML front matter (`+++`) is not supported.** Convert it to YAML.
- **Files in `static/` are not moved to the site root.** Move them into `content/` at the path you want them served from.
- **Image references** in raw HTML or shortcodes must point at the `.webp` file.

<details>
<summary><code>shortcodes_to_footnotes.py</code></summary>

```python
#!/usr/bin/env python3
"""Rewrite Hugo sidenote/marginnote shortcodes as footnotes, in place: python3 shortcodes_to_footnotes.py content/**/*.md"""
import re, sys

SHORTCODE = re.compile(r'\{\{[<%]\s*(sidenote|marginnote)\b[^}]*?[>%]\}\}(.*?)\{\{[<%]\s*/\1\s*[>%]\}\}', re.S)

for path in sys.argv[1:]:
    text = open(path, encoding='utf-8').read()
    notes = []
    def footnote(m):
        prefix = 'mn' if m.group(1) == 'marginnote' else ''
        notes.append(f'[^{prefix}{len(notes) + 1}]: ' + ' '.join(m.group(2).split()))  # notes must be one line
        return f'[^{prefix}{len(notes)}]'
    text = SHORTCODE.sub(footnote, text)
    if notes:
        open(path, 'w', encoding='utf-8').write(text.rstrip('\n') + '\n\n' + '\n'.join(notes) + '\n')
        print(f'{path}: {len(notes)} notes')
```

The script edits files in place, so commit before running it and review the `git diff` afterwards.

</details>

## Limitations

These are deliberate, to keep the generator small:

- Lists can't be nested. Tables, task lists, setext headings (text underlined with `===` or `---`) and reference-style links aren't supported.
- Footnote and note text must fit on one line.
- Code blocks aren't syntax-highlighted. Each block gets a `language-*` class if you want to add a highlighter.
- Two headings with identical text get the same anchor `id`.
- Image references must use absolute paths (`/images/…`). Relative paths aren't converted, and they break in the feed.
- Each image is produced at one size; there's no `srcset`. Images are converted again on every build.

## Licenses

- `src/vendor/tufte.css`: [tufte-css](https://github.com/edwardtufte/tufte-css), © 2014 Dave Liepmann, MIT.
- `src/vendor/daisyui.css`: [daisyUI](https://github.com/saadeghi/daisyui), MIT. The license headers are kept in the file.
