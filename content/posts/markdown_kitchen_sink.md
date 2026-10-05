---
title: "A Markdown kitchen sink"
date: 2026-10-05
lastmod: 2026-10-05T12:00:00Z
description: Every Markdown feature the generator supports, rendered in Tufte style with sidenotes, margin notes, images, lists, and code.
image: /images/landscape.svg
categories: ["essays"]
---
This post exercises every feature of the generator. Its search and social description comes from the `description` front matter, so every post should have one.[^intro]

[^intro]: Sidenotes are written as ordinary Markdown footnotes. They render in the right-hand margin and collapse behind a toggle on small screens.

## Heading level two

Section headings start at `##`. The post title is the page's only `<h1>`, so don't use `#` in content.

### Heading level three

#### Heading level four

##### Heading level five

###### Heading level six

## Inline formatting

Text can be *emphasized*, _also emphasized_, **strong**, __also strong__, or `inline code`. Snake_case_words stay intact. Links can be [inline](https://edwardtufte.github.io/tufte-css/), or bare autolinks like <https://ziglang.org>. Entities such as &mdash; and &copy; pass through, special characters like < and & are escaped, and \*escaped asterisks\* stay literal. Inline <abbr title="HyperText Markup Language">HTML</abbr> passes through too.

## Sidenotes and margin notes

Numbered sidenotes use footnote syntax.[^numbered] Unnumbered margin notes use an id starting with `mn`.[^mn-plain] Notes can hold formatting, links, and images.[^figure]

[^numbered]: This is a numbered sidenote with **bold**, *italic*, and a [link](https://github.com/WalkerGriggs).
[^mn-plain]: This margin note has no number. On mobile, tap ⊕ to reveal it.
[^figure]: ![A rising red sparkline](/images/sparkline.svg) An image inside a sidenote, which Tufte uses for small multiples and sparklines.

You can also put a picture in a margin note.[^mn-figure]

[^mn-figure]: ![A small landscape](/images/landscape.svg) Margin figures sit beside the text they describe.

## Images

![A flat landscape with hills and a sun](/images/landscape.svg)

Images are lazy-loaded and must carry alt text for accessibility and search.

## Lists

An unordered list:

- Markdown content with YAML front matter
- Tufte CSS for typography and the margin column
- daisyUI for components such as the navbar and footer
  - Lists can nest, and items can hold `code`, **formatting**, and [links](https://commonmark.org)
  - ~~Strikethrough~~ and task lists work too:
    - [x] Parse Markdown with md4c
    - [ ] Write the next post

An ordered list:

1. Walk the content directory
2. Parse front matter and render Markdown
3. Write HTML, the feed, the sitemap, and `robots.txt`
10. Numbers don't need to be sequential

## Tables

| Step | Lines | Notes |
| :--- | ---: | :---: |
| Markdown | ~60 | md4c does the parsing |
| Layout | 72 | Head, nav, footer |

## Blockquotes

> The commonality between science and art is in trying to see profoundly — to develop strategies of seeing and showing.
>
> — Edward Tufte

## Code blocks

A fenced block with a language gets a `language-*` class for highlighters:

```zig
const std = @import("std");

pub fn main() void {
    std.debug.print("hello, {s}\n", .{"world"});
}
```

```sh
zig build run -- content public
```

A fence without a language:

```
<html> & other characters are escaped inside code.
```

## Raw HTML

Blocks that start with a tag pass through untouched, which is handy for Tufte's full-width figures:

<figure class="fullwidth">
  <img src="/images/landscape.svg" alt="A full-width landscape figure">
</figure>

---

Above is a horizontal rule. That's everything.
