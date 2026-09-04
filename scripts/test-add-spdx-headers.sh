#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0
# Copyright (C) 2024-2026 Breakdown RS Contributors
# Co-authored-by: muse-spark-1.3-contributor-free (opencode)
# test-add-spdx-headers.sh - Guard test for add-spdx-headers.sh (issue #345).
#
# Runs add-spdx-headers.sh against a fixture tree containing generated files
# and asserts they are left untouched, while hand-authored files still gain a
# header. Self-contained: builds the fixture in a temp dir, cleans up on exit.
#
# Usage: ./test-add-spdx-headers.sh
# Exit status: 0 when all assertions hold, 1 otherwise.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIXTURE="$(mktemp -d)"
trap 'rm -rf "$FIXTURE"' EXIT

failures=0
fail() {
    echo "❌ FAIL: $1" >&2
    failures=$((failures + 1))
}
pass() {
    echo "✅ PASS: $1"
}

# --- Fixture: generated files that must be left untouched ---
mkdir -p "$FIXTURE/backend"
mkdir -p "$FIXTURE/frontend-flutter/vendor/breakdown_api/lib/src"
mkdir -p "$FIXTURE/frontend-flutter/lib/src"
mkdir -p "$FIXTURE/frontend-flutter/.dart_tool"

printf 'components:\n  schemas: {}\n' > "$FIXTURE/backend/openapi.yaml"
# Path-exclusion fixtures intentionally omit any GENERATED banner so each
# path predicate is tested independently of the content-level guard. Only
# future_generated.dart below exercises the content guard.
printf '// Vendor artifact — committed output of scripts/regen-client.sh.\n// other content\n' > "$FIXTURE/frontend-flutter/vendor/breakdown_api/lib/src/soll_ist_report.dart"
printf '// build_runner output\n// other content\n' > "$FIXTURE/frontend-flutter/lib/src/cache_database.g.dart"
printf '// freezed output\n// other content\n' > "$FIXTURE/frontend-flutter/lib/src/model.freezed.dart"
printf '// mockito output\n// other content\n' > "$FIXTURE/frontend-flutter/lib/src/service.mocks.dart"
printf '// GENERATED, DO NOT EDIT: future generated tree at an unknown path.\n// covered by the content-level banner guard, not the path prune.\n' > "$FIXTURE/frontend-flutter/lib/src/future_generated.dart"
printf '// some dart_tool artifact\n' > "$FIXTURE/frontend-flutter/.dart_tool/package_config.dart"

# --- Fixture: hand-authored files that must gain a header ---
mkdir -p "$FIXTURE/backend/src"
mkdir -p "$FIXTURE/frontend-flutter/lib/src"
mkdir -p "$FIXTURE/docs"
printf 'fn main() {}\n' > "$FIXTURE/backend/src/main.rs"
printf 'void main() {}\n' > "$FIXTURE/frontend-flutter/lib/src/hand_written.dart"
# Authored OpenAPI document outside backend/: must NOT match the scoped
# backend/openapi.yaml exclusion, so it still gains a header.
printf 'components:\n  schemas: {}\n' > "$FIXTURE/docs/openapi.yaml"

# Record pre-run checksums of every generated file.
declare -A before
while IFS= read -r f; do
    before["$f"]="$(sha256sum "$f" | cut -d' ' -f1)"
done < <(find "$FIXTURE/backend/openapi.yaml" \
    "$FIXTURE/frontend-flutter/vendor" \
    "$FIXTURE/frontend-flutter/lib/src/cache_database.g.dart" \
    "$FIXTURE/frontend-flutter/lib/src/model.freezed.dart" \
    "$FIXTURE/frontend-flutter/lib/src/service.mocks.dart" \
    "$FIXTURE/frontend-flutter/lib/src/future_generated.dart" \
    "$FIXTURE/frontend-flutter/.dart_tool" -type f)

# --- Act ---
bash "$SCRIPT_DIR/add-spdx-headers.sh" "$FIXTURE" > /dev/null

# --- Assert: generated files byte-identical, no SPDX injected ---
for f in "${!before[@]}"; do
    after="$(sha256sum "$f" | cut -d' ' -f1)"
    if [ "$after" != "${before[$f]}" ]; then
        fail "$f was modified (expected untouched)"
    elif grep -q "SPDX-License-Identifier" "$f"; then
        fail "$f contains an SPDX header (expected none)"
    else
        pass "$f left untouched"
    fi
done

# --- Assert: hand-authored files gained a header ---
for f in "$FIXTURE/backend/src/main.rs" "$FIXTURE/frontend-flutter/lib/src/hand_written.dart" "$FIXTURE/docs/openapi.yaml"; do
    if grep -q "SPDX-License-Identifier" "$f"; then
        pass "$f gained SPDX header"
    else
        fail "$f missing SPDX header (expected it to be added)"
    fi
done

if [ "$failures" -gt 0 ]; then
    echo "" >&2
    echo "❌ $failures assertion(s) failed." >&2
    exit 1
fi

echo ""
echo "✅ All add-spdx-headers guard assertions passed."
