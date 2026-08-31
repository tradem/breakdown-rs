#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0
# Copyright (C) 2024-2026 Breakdown RS Contributors
#
# AUTHZ-GATE verification helper (wire-flutter-oidc-auth Task 3.2).
#
# Every call site in lib/ that reaches a backend handler-internal AUTHZ-GATEd
# endpoint MUST run a client-side role check via `currentMembershipProvider`
# first, marked with a `// AUTHZ-GATE:` comment (AGENTS.md §5 / Decision D6).
#
# This script is the greppable review aid: it scans lib/ for gated-endpoint
# call sites and fails when the containing file carries no AUTHZ-GATE marker.
# It is a heuristic (the gate is a human-review requirement), meant to catch
# misses early — run it in CI alongside `grep AUTHZ-GATE` spot checks.
#
# Usage: scripts/check-authz-gates.sh   (from anywhere; resolves repo root)

set -euo pipefail

FLUTTER_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB_DIR="$FLUTTER_ROOT/lib"

# Gated backend endpoints (handler-internal AUTHZ-GATE per backend AGENTS.md):
# photo upload (`/costumes/{id}/photos`), photo byte fetch, photo delete,
# continuity-photo handlers. Path-fragment patterns, matched against
# non-comment source lines. Extend as the backend grows more gated handlers.
GATED_PATTERNS=(
  'continuity-photos'
  '/photos'
  '/bytes'
)

# The gate is enforced at the command-DISPATCH layer (features/domain/auth
# providers and widgets): that is where a check can run before the network
# call. `lib/data/` repositories are pure transport and deliberately exempt —
# they neither know the season context nor hold Riverpod refs.
SCAN_DIRS=(
  "$LIB_DIR/features"
  "$LIB_DIR/domain"
  "$LIB_DIR/auth"
)

# A file satisfies the convention when it contains the marker comment AND a
# membership check. Files with no gated calls at all are ignored.
has_gate() {
  local file="$1"
  grep -q 'AUTHZ-GATE' "$file" &&
    grep -q 'currentMembershipProvider' "$file"
}

# True when the file calls a gated endpoint on a NON-comment line (doc
# comments mentioning endpoints don't count).
calls_gated() {
  local file="$1" pattern="$2"
  grep -v '^[[:space:]]*///' "$file" | grep -v '^[[:space:]]*//' \
    | grep -q -e "$pattern"
}

violations=0
for dir in "${SCAN_DIRS[@]}"; do
  [ -d "$dir" ] || continue
  for pattern in "${GATED_PATTERNS[@]}"; do
    while IFS= read -r -d '' file; do
      if calls_gated "$file" "$pattern" && ! has_gate "$file"; then
        echo "MISSING AUTHZ-GATE: $file (calls gated endpoint '$pattern')"
        violations=$((violations + 1))
      fi
    done < <(grep -rZl --include='*.dart' -e "$pattern" "$dir" 2>/dev/null || true)
  done
done

if [ "$violations" -gt 0 ]; then
  echo
  echo "$violations file(s) call gated endpoints without a client-side"
  echo "AUTHZ-GATE (a '// AUTHZ-GATE:' comment plus a currentMembershipProvider"
  echo "check before the network call). See AGENTS.md §5 (Decision D6)."
  exit 1
fi

echo "AUTHZ-GATE check passed."
