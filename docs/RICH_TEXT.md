# Rich Text Guide

This document describes how the server handles rich text in Apple Notes.

## Overview

- Apple Notes stores note bodies as HTML-like content.
- Read tools can render that content as:
  - `plain` text
  - `markdown`
  - raw `html`
- Write tools can accept:
  - `plain` input
  - `html` input (rich text)
  - `markdown` input (converted to Notes-friendly rich HTML)

Apple Notes HTML is not generic browser HTML. This server targets a conservative
subset that Notes preserves reliably.

## Read Behavior

Tools:

- `get_note` supports `bodyFormat: "plain" | "markdown" | "html"`.
- `list_notes` supports `bodyFormat` only when `includeBody=true`.
- `batch_get_notes` supports `bodyFormat` for per-note body output.

Important:

- Internally, parser helpers keep raw HTML.
- `list_notes` body search always matches on plain text derived from HTML.
- Output formatting happens at tool edges.
- `bodyFormat=html` returns raw stored Notes HTML unchanged.

## Markdown Rendering Rules

`BodyFormatter` maps Notes HTML to markdown with these priorities:

- `h1/h2/h3` -> `# / ## / ###`
- `b/strong` -> `**...**`
- `i/em` -> `*...*`
- `u` -> preserved inline as `<u>...</u>`
- `strike/s/del` -> `~~...~~`
- `tt/code` -> `` `...` ``
- `ul/ol/li` -> markdown lists
- `a[href]` -> `[text](url)`
- simple rectangular `<table>` -> markdown table
- complex `<table>` -> raw HTML fallback
- `<img ...>` -> `[Attachment]`
- unsupported `<object ...>` blocks -> `[Embedded Content]`

## Write Behavior

Tool:

- `create_note` supports `bodyFormat: "plain" | "html" | "markdown"`.
- `create_note` injects the caller title as the first rich heading in the body.
- After note creation, `create_note` sets metadata `name` to the same title to keep Notes metadata and visible heading aligned without duplicate title lines.

`bodyFormat=plain`:

- escapes `&`, `<`, `>`
- normalizes newlines
- converts newline to `<br>`

`bodyFormat=html`:

- passes provided HTML through as rich body content
- only applies AppleScript string escaping for transport safety

`bodyFormat=markdown`:

- parses markdown with `swift-markdown` (AST-based, not regex parsing)
- converts supported markdown blocks/spans into Notes-friendly HTML
- then writes resulting HTML via the normal rich-text path

Title rendering limitation:

- Apple Notes may normalize heading HTML when persisting note bodies.
- A written `<h1>` title can be returned later as style-based markup (for example bold text with large font size) instead of a literal `<h1>` element.

Literal markdown contract:

- if callers want raw markdown text stored verbatim, they must use
  `bodyFormat="plain"`.
- `bodyFormat="markdown"` always transforms markdown into rich HTML.

## Markdown Write Mapping (v1)

The markdown renderer currently supports:

- headings `#`, `##`, `###` -> `<h1>`, `<h2>`, `<h3>`
- paragraphs -> `<div>...</div>`
- unordered/ordered lists -> `<ul>/<ol>/<li>`
- bold/italic/strikethrough -> `<b>/<i>/<strike>`
- inline code -> `<code>`
- links -> `<a href="...">...</a>`
- soft line breaks -> spaces, hard line breaks -> `<br>`

Fallback/degraded rendering:

- blockquote -> rendered as a prefixed plain line (`&gt; ...`) in a `<div>`
- thematic break (`---`) -> rendered as `<div>---</div>`
- unsupported nodes -> flattened to readable text

This keeps output deterministic for agents while avoiding unsupported Notes HTML
constructs.

## Agent Authoring Recommendations

When writing rich content (`bodyFormat="html"` or `bodyFormat="markdown"`), prefer this subset:

- block structure: `<div>`, `<br>`
- headings: `<h1>`, `<h2>`, `<h3>`
- inline emphasis: `<b>`, `<i>`, `<u>`, `<strike>`, `<tt>`
- lists: `<ul>/<ol>/<li>`
- links: `<a href="...">`
- tables: `<table>/<tr>/<td>`

Keep HTML predictable and avoid custom scripting/content that Notes may strip.
