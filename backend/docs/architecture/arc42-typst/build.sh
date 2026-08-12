#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0
# Copyright (C) 2024-2026 Breakdown RS Contributors
# Co-authored-by: kimi-k3 (neuralwatt)

# Build the arc42 architecture documentation (PDF + HTML) with PlantUML diagrams.
# SVGs are generated into ./diagrams/ from ../diagrams/*.puml before compilation.
#
# Environment variables:
#   DOCS_VERSION    — build version (default: "dev")
#   DOCS_BUILD_DATE — build date, YYYY-MM-DD (default: today, via Typst fallback)
#   PLANTUML_IMAGE  — container image for diagram rendering
#                     (default: plantuml/plantuml:latest)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

DOCS_VERSION="${DOCS_VERSION:-dev}"
DOCS_BUILD_DATE="${DOCS_BUILD_DATE:-$(date +%F)}"
PLANTUML_IMAGE="${PLANTUML_IMAGE:-plantuml/plantuml:latest}"

echo "🔨 arc42 build  (version: $DOCS_VERSION, date: $DOCS_BUILD_DATE)"
echo "   diagrams  : ../diagrams/*.puml → ./diagrams/*.svg"
echo ""

# --- prerequisites ---
if ! command -v typst &>/dev/null; then
  echo "❌ typst not found. Install: https://github.com/typst/typst/releases"
  exit 1
fi

# --- generate SVGs from PlantUML ---
mkdir -p diagrams dist

if command -v plantuml &>/dev/null; then
  # local installation
  plantuml -tsvg -o "$SCRIPT_DIR/diagrams" ../diagrams/*.puml
else
  # container-based (CI or local with Docker)
  if ! command -v docker &>/dev/null; then
    echo "❌ Neither 'plantuml' nor 'docker' found. Cannot render diagrams."
    echo "   Install one: plantuml (https://plantuml.com/starting)"
    echo "               docker (https://docs.docker.com/get-docker/)"
    exit 1
  fi
  echo "🐳 Rendering diagrams via Docker ($PLANTUML_IMAGE)..."
  docker run --rm \
    -v "$SCRIPT_DIR/../diagrams:/src:ro" \
    -v "$SCRIPT_DIR/diagrams:/out" \
    "$PLANTUML_IMAGE" \
    -tsvg -o /out /src/*.puml
fi

echo "   SVG count: $(ls diagrams/*.svg 2>/dev/null | wc -l)"
echo ""

# --- compile PDF ---
echo "📄 Compiling PDF → dist/architecture-v${DOCS_VERSION}.pdf"
typst compile main.typ "dist/architecture-v${DOCS_VERSION}.pdf" \
  --input version="${DOCS_VERSION}" \
  --input build-date="${DOCS_BUILD_DATE}"

# --- compile HTML ---
# HTML export is a document feature flag (`--features html`), not a Cargo
# feature. The official GitHub release binaries support it; distro packages
# (e.g. Arch) may not. It is experimental — CI treats warnings as non-fatal.
echo "🌐 Compiling HTML → dist/architecture-v${DOCS_VERSION}.html"
if ! typst compile main.typ "dist/architecture-v${DOCS_VERSION}.html" \
  --features html \
  --format html \
  --input version="${DOCS_VERSION}" \
  --input build-date="${DOCS_BUILD_DATE}" 2>&1; then
  echo "⚠️  HTML build failed - requires typst supporting '--features html'."
  echo "   Install the official binary from https://github.com/typst/typst/releases"
  echo "   Continuing without HTML output..."
fi

echo ""
echo "✅ Build complete."
echo "   📄 dist/architecture-v${DOCS_VERSION}.pdf"
echo "   🌐 dist/architecture-v${DOCS_VERSION}.html"
echo "   🖼  diagrams/: $(ls diagrams/*.svg | wc -l) SVG files"
