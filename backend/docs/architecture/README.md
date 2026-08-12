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

## CI pipeline (`docs.yml`)

The workflow `.github/workflows/docs.yml`:

1. Renders PlantUML sources to SVG (Docker image, digest-pinned).
2. Installs the pinned Typst CLI and builds PDF + HTML (version from the
   `api-vX.Y.Z` tag, or `dev-<sha>` on main).
3. On `main`: publishes the HTML to GitHub Pages (always latest).
4. On `api-v*` tags: attaches the versioned PDF + HTML to the GitHub Release.

> Repository setting required once: *Settings → Pages → Build and deployment
> source: GitHub Actions*.

## Adding diagrams

1. Create or edit `diagrams/<name>.puml` (PlantUML, SPDX header optional).
2. Run `./build.sh` to regenerate SVGs.
3. Reference in a chapter: `#diagram("<name>", caption: […])`.

Generated SVGs are git-ignored; commit only `.puml` files.

## arc42 chapters

The Typst entry point is `arc42-typst/main.typ`. Chapters follow the
official arc42 numbering (01–12).

