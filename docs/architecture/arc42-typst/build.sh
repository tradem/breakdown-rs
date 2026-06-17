#!/bin/bash
# Build script for arc42 architecture documentation (Typst version)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "🔨 Building arc42 architecture documentation with Typst..."

# Check if typst is installed
if ! command -v typst &> /dev/null; then
    echo "❌ Typst is not installed."
    echo ""
    echo "Installation options:"
    echo "  1. Via Cargo: cargo install --git https://github.com/typst/typst --locked"
    echo "  2. Download binary: https://github.com/typst/typst/releases"
    echo ""
    exit 1
fi

# Create output directory
mkdir -p dist

# Build PDF
echo "📄 Compiling main.typ -> dist/architecture.pdf..."
typst compile main.typ dist/architecture.pdf

echo "✅ Build complete: dist/architecture.pdf"
echo ""
echo "📊 File size: $(du -h dist/architecture.pdf | cut -f1)"
