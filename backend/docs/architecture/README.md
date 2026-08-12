<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: kimi-k3 (neuralwatt) -->

# Architecture Documentation

This directory is the single source of truth for architecture documentation.

```
docs/architecture/
├── adrs/                 # Architecture Decision Records (Markdown)
├── arc42-typst/          # arc42 architecture documentation (Typst)
├── diagrams/             # PlantUML diagram sources (*.puml)
├── spikes/               # Research spikes
└── templates/            # Shared templates
```

## Multi-format strategy (ADR-008)

| Type | Format | Tool | Hosting |
|------|--------|------|---------|
| ADRs | Markdown | (none) | GitHub (versioned) |
| arc42 | Typst | `typst` CLI | GitHub Releases (PDF), GitHub Pages (HTML) |
| Diagrams | PlantUML | `-tsvg` via Docker or local | embedded into the above |

## Building the arc42 documentation

From `docs/architecture/arc42-typst/`:

```bash
# one-shot (uses Docker for PlantUML rendering)
./build.sh

# override version / date (used by CI for releases)
DOCS_VERSION=1.2.3 DOCS_BUILD_DATE=2026-01-01 ./build.sh
```

Artifacts are written to `dist/`.

## Adding diagrams

1. Create or edit `diagrams/<name>.puml` (PlantUML, SPDX header optional).
2. Run `./build.sh` to regenerate SVGs.
3. Reference in a chapter: `#diagram("<name>", caption: […])`.

Generated SVGs are git-ignored; commit only `.puml` files.

## arc42 chapters

The Typst entry point is `arc42-typst/main.typ`. Chapters follow the
official arc42 numbering (01–12).

<!-- The CI workflow `docs.yml` (to be added) publishes PDF and HTML from every release tag. -->
