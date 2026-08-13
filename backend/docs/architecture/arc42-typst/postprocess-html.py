#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0
# Copyright (C) 2024-2026 Breakdown RS Contributors
# Co-authored-by: deepseek-v4-flash (opencode-go)

"""Post-process the arc42 HTML export for the GitHub Pages presentation layer.

Typst's HTML export (``--features html``) is experimental and emits an unstyled
document (issue #235):

- Tables export as real ``<table>/<tr>/<td>`` markup, but with no CSS the grid
  is invisible — the page shows a text-only dump.
- PlantUML diagrams are embedded as ``<img>`` data URIs. The exporter stamps
  every image with the SVG's fixed pixel dimensions as HTML attributes plus an
  inline ``style="display: block; width: 100%"``. The width attribute is
  overridden by the CSS width, while the fixed height attribute stays — so the
  browser scales width and height independently and the SVG is squashed or
  stretched.

This script injects a small ``<style>`` block before ``</head>`` that:

1. Makes images proportional at their natural size, capped by the container:
   ``width: auto !important`` (beats the exporter's inline ``width: 100%``),
   ``max-width: 100%``, ``height: auto``.
2. Gives tables visible column/row structure (borders, header shading).
3. Centers figures and styles the caption.

It fails loudly if the expected document structure is missing, so a future
Typst export change cannot silently regress the Pages site.

Usage: postprocess-html.py <path-to-html>
"""

import re
import sys

PAGES_STYLE = """
figure img {
  /* The experimental exporter stamps every diagram with its intrinsic pixel
     size and an inline `width: 100%`. Without a matching height the browser
     scales the two axes independently and distorts PlantUML SVGs (issue
     #235). Force proportional, natural-size rendering capped by the
     container. Scoped to `figure img` (all diagrams live in figures) so
     future inline images keep the exporter's width. `!important` is required
     to override the inline width. */
  width: auto !important;
  max-width: 100%;
  height: auto;
}

img {
  /* Safety net for images outside figures. */
  max-width: 100%;
  height: auto;
}

table {
  border-collapse: collapse;
  margin: 1em 0;
}

th, td {
  border: 1px solid #888;
  padding: 0.25em 0.6em;
  text-align: left;
  vertical-align: top;
}

th {
  background-color: #f2f2f2;
}

figure {
  margin: 1em 0;
  text-align: center;
}

figcaption {
  font-size: 0.85em;
  color: #555;
  margin-top: 0.4em;
}
"""


def main() -> int:
    if len(sys.argv) != 2:
        print(f"usage: {sys.argv[0]} <path-to-html>", file=sys.stderr)
        return 2

    path = sys.argv[1]
    try:
        html = open(path, encoding="utf-8").read()
    except OSError as exc:
        print(f"cannot read {path}: {exc}", file=sys.stderr)
        return 1

    # Structural guards: the fixes below depend on the exporter's output shape.
    if "</head>" not in html:
        print(
            "postprocess-html.py: no </head> found — cannot inject the style "
            "block. Typst HTML export structure changed?",
            file=sys.stderr,
        )
        return 1
    if "<table" not in html:
        print(
            "postprocess-html.py: no <table> elements found — the document "
            "lost its tables (Markdown pipe syntax regressed?).",
            file=sys.stderr,
        )
        return 1
    if "<img" not in html:
        print(
            "postprocess-html.py: no <img> elements found — nothing to keep "
            "proportional.",
            file=sys.stderr,
        )
        return 1

    style = f"<style>{PAGES_STYLE}</style>"
    if style in html:
        # Idempotent: re-running on an already-processed file is a no-op.
        return 0

    html = html.replace("</head>", style + "</head>", 1)
    try:
        with open(path, "w", encoding="utf-8") as out:
            out.write(html)
    except OSError as exc:
        print(f"cannot write {path}: {exc}", file=sys.stderr)
        return 1

    print(f"postprocess-html.py: injected style block into {path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
