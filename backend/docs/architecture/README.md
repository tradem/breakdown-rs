<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: kimi-k3 (neuralwatt) -->
<!-- Co-authored-by: gemini-4-carbon (google) -->

# Architecture Documentation

This directory holds the architecture documentation for the Breakdown RS monorepo.

```text
docs/architecture/
├── adrs/                 # Architecture Decision Records (Markdown, ADR-001..040)
├── arc42-typst/          # arc42 architecture documentation in Typst (ASD-STE100)
├── diagrams/             # PlantUML diagram sources (*.puml)
└── spikes/               # Research spikes
```

## Language and Format Strategy (ADR-008)

All chapters in `arc42-typst/` use **ASD-STE100 Simplified Technical English
(STE)**. Chapter 12 (*Glossary*) defines the approved project Technical Names
(TN) and Technical Verbs (TV).

| Type | Format | Tool | Hosting |
|------|--------|------|---------|
| ADRs | Markdown | (none) | GitHub repository (versioned) |
| arc42 | Typst (ASD-STE100) | `typst` CLI | GitHub Releases (PDF + HTML), GitHub Pages (HTML) |
| Diagrams | PlantUML | `plantuml -tsvg` | Embedded into arc42 PDF and HTML |

## Build the arc42 Documentation

Run `./build.sh` from `backend/docs/architecture/arc42-typst/`:

```bash
# Default local build (uses Docker if local plantuml is absent)
./build.sh

# Override version and build date (used by CI on release tags)
DOCS_VERSION=1.2.3 DOCS_BUILD_DATE=2026-01-01 ./build.sh
```

The script writes PDF and HTML artifacts to `arc42-typst/dist/`.

`postprocess-html.py` runs automatically at the end of `build.sh` (issue #235).
It injects a `<style>` block into the Typst HTML export so tables show a grid
and PlantUML SVG diagrams keep their aspect ratio.

## CI Pipeline (`docs.yml`)

The workflow `.github/workflows/docs.yml` executes four steps:

1. Render `diagrams/*.puml` to SVG with the digest-pinned PlantUML container.
2. Install the pinned Typst CLI, compile PDF and HTML, and run `postprocess-html.py`.
3. Publish the HTML file to GitHub Pages on pushes to `main`.
4. Attach the versioned PDF and HTML files to the GitHub Release on `api-v*` tags.

## Add or Update Diagrams

1. Edit or create `diagrams/<name>.puml` with an `AGPL-3.0` SPDX header.
2. Run `./build.sh` in `arc42-typst/` to render the SVG files.
3. Reference the diagram in a Typst chapter with `#diagram("<name>", caption: […])`.

Git ignores generated `arc42-typst/diagrams/*.svg` and `arc42-typst/dist/*`
files. Commit only the `.puml` and `.typ` sources.

## arc42 Chapters

`arc42-typst/main.typ` includes all official arc42 chapters (`01` to `12`).
