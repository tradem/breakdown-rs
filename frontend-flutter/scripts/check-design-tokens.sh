#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0
# Copyright (C) 2024-2026 Breakdown RS Contributors
#
# Design-token verification helper (flutter-login-and-app-shell, spec
# `flutter-design-tokens`).
#
# Widgets introduced by the login-and-app-shell change must use scheme roles
# (`Theme.of(context).colorScheme`) and `lib/design` tokens — a `Color(...)`
# literal in widget code is rejected at review (spec scenario "Hardcoded
# color in a new widget"; design.md §5).
#
# This script is the greppable review aid: it scans widget code and fails on
# `Color(` constructions. It is a heuristic (doc comments don't count) —
# run it in review alongside `grep Color(` spot checks. Known documented
# deviation (design.md §5): `FatalConfigErrorApp` in `lib/app.dart` renders
# before theming exists and is exempt.
#
# Usage: scripts/check-design-tokens.sh   (from anywhere; resolves repo root)

set -euo pipefail

FLUTTER_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB_DIR="$FLUTTER_ROOT/lib"

# Widget code under review (generated + vendored trees are rebuild-only and
# out of scope; `lib/design` OWNS the tokens by definition).
SCAN_DIRS=(
  "$LIB_DIR/features"
  "$LIB_DIR/auth"
  "$LIB_DIR/design"
)

# Files exempt with documented reason (design.md §5).
EXEMPT_FILES=(
  "$LIB_DIR/app.dart"
)

is_exempt() {
  local file="$1"
  for exempt in "${EXEMPT_FILES[@]}"; do
    [ "$file" = "$exempt" ] && return 0
  done
  return 1
}

violations=0
for dir in "${SCAN_DIRS[@]}"; do
  [ -d "$dir" ] || continue
  while IFS= read -r -d '' file; do
    if is_exempt "$file"; then
      continue
    fi
    # Non-comment lines only; word-boundary so `ColorScheme(` never matches.
    if grep -v '^[[:space:]]*///' "$file" | grep -v '^[[:space:]]*//' \
      | grep -q -e '\<Color('; then
      echo "HARDCODED COLOR: $file (use color-scheme roles or lib/design)"
      violations=$((violations + 1))
    fi
  done < <(grep -rZl --include='*.dart' -e 'Color(' "$dir" 2>/dev/null || true)
done

if [ "$violations" -gt 0 ]; then
  echo
  echo "$violations file(s) with hardcoded Color(...) outside lib/design/."
  echo "See spec flutter-design-tokens and design.md §5 (D3)."
  exit 1
fi

echo "Design-token check passed."
