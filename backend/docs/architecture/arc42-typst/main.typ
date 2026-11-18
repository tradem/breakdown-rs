// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: kimi-k3 (neuralwatt)
// Co-authored-by: gemini-4-carbon (google)

// Breakdown RS - Architecture Documentation
// arc42 Template in Typst (ASD-STE100 Simplified Technical English)
// Based on: https://arc42.org/template/

#import "template.typ": *

// The build injects version and build-date as CLI inputs:
//   typst compile main.typ dist/architecture.pdf \
//     --input version=1.2.3 --input build-date=2026-01-01
// Local preview builds default to "dev" and today's date.
#let version = sys.inputs.at("version", default: "dev")
#let build-date = sys.inputs.at(
  "build-date",
  default: datetime.today().display("[year]-[month]-[day]"),
)

#show: doc.with(
  title: "Breakdown RS: Architecture Documentation",
  subtitle: "Collaborative Costume Scheduling and Scene Continuity",
  version: version,
  date: build-date,
  authors: ("Tobias Rademacher (@tradem)",),
  co-authors: (
    "kimi-k3 (neuralwatt)",
    "ox-alpha-free (opencode-go)",
    "gemini-4-carbon (google)",
  ),
)

= About this Document

This document describes the software architecture of the Breakdown RS monorepo.
It follows the #link("https://arc42.org/")[arc42] structure and uses
*ASD-STE100 Simplified Technical English (STE)*.

*System scope*: This document covers both the event-sourced Rust backend
(`backend/`) and the Flutter client (`frontend-flutter/`). OpenSpec governance
files live at the monorepo root (`/openspec/`).

*Language standard*: All prose follows ASD-STE100 rules for active voice,
short sentences, and approved vocabulary. Chapter 12 defines all project-specific
Technical Names (TN) and Technical Verbs (TV).

*Source of truth*: All Typst chapters live in
`backend/docs/architecture/arc42-typst/`. Architecture Decision Records live in
#link("https://github.com/tradem/breakdown-rs/tree/main/backend/docs/architecture/adrs")[`backend/docs/architecture/adrs/`].

*Diagrams*: PlantUML sources live in `backend/docs/architecture/diagrams/*.puml`.
The `./build.sh` script renders them to SVG before Typst compiles the document.

*Outputs*: The CI workflow `.github/workflows/docs.yml` builds PDF and HTML
files from this source. GitHub Pages hosts the latest HTML from `main`. On
`api-vX.Y.Z` tags, CI creates the release with the versioned PDF and HTML files
attached and skips upload if that release already exists.

#pagebreak()

// Include all 12 arc42 chapters
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

== Build Procedure

=== Prerequisites

Install these tools before you build the documentation:

- #link("https://typst.app/")[Typst] CLI version 0.15.1 (pinned to match `crates/infra` reporting).
- Python 3 (necessary for the HTML style post-processor).
- Docker or a local `plantuml` installation on `PATH`.

=== Full Build

+ Change to the `backend/docs/architecture/arc42-typst` directory.
+ Run `./build.sh` to render all diagrams and compile PDF and HTML into `dist/`.
+ Set `DOCS_VERSION` and `DOCS_BUILD_DATE` if you need a release build.

```bash
cd backend/docs/architecture/arc42-typst
./build.sh
DOCS_VERSION=1.2.3 DOCS_BUILD_DATE=2026-01-01 ./build.sh
```

=== Manual Build Steps

+ Render the PlantUML sources to SVG files with Docker or local `plantuml`.
+ Create the `dist/` output directory.
+ Compile the PDF output with `typst compile`.
+ Compile the HTML output with `--features html --format html`.
+ Run `postprocess-html.py` to add table borders and proportional image rules.

```bash
# 1a. Render PlantUML diagrams to SVG with Docker
mkdir -p diagrams
docker run --rm \
  -v ../diagrams:/src:ro \
  -v ./diagrams:/out \
  plantuml/plantuml:1.2026.6 -tsvg -o /out /src/*.puml

# 1b. Alternative: render with a local plantuml installation
plantuml -tsvg -o ./diagrams ../diagrams/*.puml

# 2. Create dist/ and compile PDF and HTML
mkdir -p dist
typst compile main.typ dist/architecture.pdf \
  --input version=1.2.3 --input build-date=2026-01-01
typst compile main.typ dist/architecture.html \
  --features html --format html \
  --input version=1.2.3 --input build-date=2026-01-01

# 3. Apply the GitHub Pages CSS layer
python3 postprocess-html.py dist/architecture.html

# Optional: run live PDF preview while you edit chapters
typst watch main.typ dist/architecture.pdf
```

== Tool Comparison

#table(
  columns: 3,
  table.header([Feature], [Typst], [AsciiDoc]),
  [Runtime dependencies], [Single Rust binary], [Ruby and Gems],
  [Compile time], [Milliseconds], [Seconds],
  [PDF output], [Built-in], [Needs extra plugins],
  [HTML output], [Built-in (`--format html`)], [Needs extra plugins],
  [Markup syntax], [Compact and readable], [Verbose],
)

== Repository Layout

#table(
  columns: 2,
  table.header([Path], [Purpose]),
  [`backend/`], [Event-sourced Rust workspace (`core`, `infra`, `api`, test crates)],
  [`backend/openapi.yaml`], [Code-first OpenAPI wire contract],
  [`backend/docs/architecture/arc42-typst/`], [Typst source files for this document],
  [`backend/docs/architecture/diagrams/`], [Versioned PlantUML diagram sources (`*.puml`)],
  [`backend/docs/architecture/adrs/`], [Architecture Decision Records (ADR-001 to ADR-040)],
  [`frontend-flutter/`], [Layered Flutter client (Android first, Riverpod, Drift)],
  [`openspec/`], [Monorepo OpenSpec specifications and archived changes],
  [`docs/design/`], [UI glossary, screen specifications, and Salt wireframes],
)
