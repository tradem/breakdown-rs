#!/bin/bash
# add-spdx-headers.sh - Add SPDX license headers to source files
# Usage: ./add-spdx-headers.sh [directory]
# Defaults to current directory if no argument provided

set -e

LICENSE="AGPL-3.0"
COPYRIGHT="Copyright (C) 2024 Breakdown RS Contributors"
YEAR=$(date +%Y)

# If year differs from 2024, use range
if [ "$YEAR" != "2024" ]; then
    COPYRIGHT="Copyright (C) 2024-$YEAR Breakdown RS Contributors"
fi

# Find supported source files recursively. Covers the Rust backend and the
# frontend-flutter tree (Dart, Gherkin .feature, YAML).
find "${1:-.}" -type f \
    \( -name "*.rs" -o -name "*.typ" -o -name "*.sh" \
       -o -name "*.dart" -o -name "*.feature" \
       -o -name "*.yaml" -o -name "*.yml" \) | while read -r file; do
    # Check if header already exists
    if grep -q "SPDX-License-Identifier" "$file"; then
        echo "⏭️  Skipping (already has header): $file"
        continue
    fi

    # Create temp file with header + original content
    temp_file=$(mktemp)

    # Add header based on file type
    case "$file" in
        *.rs|*.typ|*.dart)
            # Rust/Typst/Dart: use // comments
            echo "// SPDX-License-Identifier: $LICENSE" > "$temp_file"
            echo "// $COPYRIGHT" >> "$temp_file"
            echo "" >> "$temp_file"
            cat "$file" >> "$temp_file"
            ;;
        *.sh|*.feature|*.yaml|*.yml)
            # Shell/Gherkin/YAML: use # comments
            echo "# SPDX-License-Identifier: $LICENSE" > "$temp_file"
            echo "# $COPYRIGHT" >> "$temp_file"
            echo "" >> "$temp_file"
            cat "$file" >> "$temp_file"
            ;;
        *)
            echo "⚠️  Unsupported file type: $file"
            continue
            ;;
    esac

    # Replace original file
    mv "$temp_file" "$file"
    echo "✅ Added header to: $file"
done

echo ""
echo "✅ Done! Added SPDX headers to all source files."
echo "📋 License: $LICENSE"
echo "📋 Copyright: $COPYRIGHT"
