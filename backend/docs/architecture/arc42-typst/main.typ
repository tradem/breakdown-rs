// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: kimi-k3 (neuralwatt)

// Breakdown RS - Architecture Documentation
// arc42 Template in Typst
// Based on: https://arc42.org/template/

#import "template.typ": *

// Version and build date are injected at build time:
//   typst compile main.typ dist/architecture.pdf \
//     --input version=1.2.3 --input build-date=2026-01-01
// The CLI falls back to "dev" and today's date for local preview builds.
#let version = sys.inputs.at("version", default: "dev")
#let build-date = sys.inputs.at(
  "build-date",
  default: datetime.today().display("[year]-[month]-[day]"),
)

#show: doc.with(
  title: "Breakdown RS — Architecture Documentation",
  subtitle: "Collaborative Costume Scheduling & Scene Continuity",
  version: version,
  date: build-date,
  authors: ("Tobias Rademacher (@tradem)",),
  co-authors: ("kimi-k3 (neuralwatt)",),
)

= About this Document

This document describes the architecture of Breakdown RS following the
#link("https://arc42.org/")[arc42] template.

*Source of truth*: `backend/docs/architecture/arc42-typst/` — all chapters, the
template, and the build script live next to the Architecture Decision Records
(#link("https://github.com/tradem/breakdown-rs/tree/main/backend/docs/architecture/adrs")[ADRs])
in `backend/docs/architecture/`.

*Diagrams*: All diagrams are written in PlantUML (`../diagrams/*.puml`) and
rendered to SVG by `./build.sh` before Typst compilation.

*Outputs*: PDF and HTML are built from this single source; the versioned PDF is
attached to each API release.

#pagebreak()

// Include all arc42 chapters
#include "01-introduction-and-goals.typ"
#include "02-architecture-constraints.typ"
#include "03-system-scope-context.typ"
#include "04-solution-strategy.typ"
#include "05-building-block-view.typ"
#include "06-runtime-view.typ"
#include "07-deployment-view.typ"
#include "08-crosscutting-concepts.typ"
#include "09-architecture-decisions.typ"
#include "10-quality-requirements.typ"
#include "11-risks-technical-debt.typ"
#include "12-glossary.typ"

#pagebreak()

= Appendix

== Build Instructions

=== Prerequisites

- #link("https://typst.app/")[Typst] CLI (matching the version pinned by the
  reporting feature in `crates/infra`, currently 0.15.1)
- A container runtime for the PlantUML rendering step (Docker or compatible);
  alternatively a local `plantuml` JAR on `PATH`

=== Full build (diagrams + PDF + HTML)

```bash
cd backend/docs/architecture/arc42-typst
./build.sh                              # PDF + HTML into dist/
DOCS_VERSION=1.2.3 DOCS_BUILD_DATE=2026-01-01 ./build.sh
```

=== Manual steps

```bash
# 1. Render PlantUML diagrams to SVG (via Docker, image overridable)
docker run --rm \
  -v ../diagrams:/src:ro \
  -v ./diagrams:/out \
  plantuml/plantuml:latest -tsvg -o /out /src/*.puml

# 2. Compile the document
#    HTML export requires the `html` feature flag (Typst 0.15).
typst compile main.typ dist/architecture.pdf \
  --input version=1.2.3 --input build-date=2026-01-01
typst compile main.typ dist/architecture.html \
  --features html \
  --format html --input version=1.2.3 --input build-date=2026-01-01

# Watch mode for writing (PDF preview only)
typst watch main.typ dist/architecture.pdf
```

== Tooling Comparison

| Feature | Typst | AsciiDoc |
|---------|-------|----------|
| Dependencies | Single binary | Ruby + Gems |
| Compilation speed | Milliseconds | Seconds |
| PDF output | Native | Needs extensions |
| HTML output | Native (`--format html`) | Needs extensions |
| Syntax | Intuitive | Verbose |

== Directory Layout

| Path | Purpose |
|------|---------|
| `arc42-typst/main.typ` | Document entry point (this file) |
| `arc42-typst/template.typ` | Styling template + helpers |
| `arc42-typst/0x-*.typ` | arc42 chapters |
| `arc42-typst/diagrams/` | Generated SVGs (git-ignored, created by build) |
| `../diagrams/*.puml` | PlantUML diagram sources (versioned) |
| `../adrs/` | Architecture Decision Records (Markdown) |

// This is a living document. Update it as the architecture evolves.
