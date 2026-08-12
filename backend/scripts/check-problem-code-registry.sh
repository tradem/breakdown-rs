#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0
# Copyright (C) 2024-2026 Breakdown RS Contributors
# Co-authored-by: deepseek-v4-flash (opencode-go)

# Shared checker for the problem-code-registry guardrail (issue #232).
#
# Every `pub const <NAME>: ProblemCode` must be declared through the
# `problem_codes!` macro in crates/core/src/error_registry.rs; a standalone
# declaration compiles but is never registered (problem_code() returns None,
# the bundle-coverage lint never fires, the uniqueness test never sees it).
#
# This script is the single implementation invoked by both the
# `problem-code-registry` CI job (architecture-checks.yml) and the pre-commit
# hook — do not inline the check anywhere else.
#
# Syntax-aware via ast-grep: the rule rules/problem-code-registry.yml matches
# canonical, spaced and multiline declarations alike, and does not bind to the
# macro's `pub const $name` expansion template (verified by the rule tests in
# rules-tests/, run with --self-test).
#
# Fail-closed: a missing scanner/rule, a scanner crash, or unparseable scanner
# output all fail the script; only a clean scan with zero matches passes.
#
# Usage:
#   check-problem-code-registry.sh [TARGET...]   # scan paths (default: crates/)
#   check-problem-code-registry.sh --self-test   # run the rule test-suite

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

RULE="rules/problem-code-registry.yml"

if [ "${1:-}" = "--self-test" ]; then
    command -v ast-grep >/dev/null 2>&1 || {
        echo "ERROR: ast-grep is required for the problem-code-registry self-test" >&2
        exit 1
    }
    [ -f sgconfig.yml ] || {
        echo "ERROR: sgconfig.yml not found — run from backend/" >&2
        exit 1
    }
    ast-grep test -c sgconfig.yml -t rules-tests
    exit $?
fi

TARGETS=("$@")
if [ "${#TARGETS[@]}" -eq 0 ]; then
    TARGETS=(crates/)
fi

command -v ast-grep >/dev/null 2>&1 || {
    echo "ERROR: ast-grep is required for the problem-code-registry check" >&2
    exit 1
}
command -v python3 >/dev/null 2>&1 || {
    echo "ERROR: python3 is required to parse the ast-grep output" >&2
    exit 1
}
[ -f "$RULE" ] || {
    echo "ERROR: rule file not found: $RULE" >&2
    exit 1
}

ERR=$(mktemp)
trap 'rm -f "$ERR"' EXIT

rc=0
OUT=$(ast-grep scan -r "$RULE" --json "${TARGETS[@]}" 2>"$ERR") || rc=$?
if [ "$rc" -ne 0 ] && [ "$rc" -ne 1 ]; then
    echo "ERROR: ast-grep scanner failed (exit $rc) — failing closed" >&2
    cat "$ERR" >&2
    exit 1
fi

if [ "$rc" -eq 0 ]; then
    echo "OK: every ProblemCode constant is declared through the registry macro"
    exit 0
fi

# rc == 1: at least one violation. Report each and fail.
report_rc=0
python3 - "$OUT" <<'PYEOF' || report_rc=$?
import json
import sys

try:
    matches = json.loads(sys.argv[1])
except json.JSONDecodeError as exc:  # pragma: no cover - scanner error path
    print(f"ERROR: cannot parse ast-grep JSON output ({exc}) — failing closed", file=sys.stderr)
    sys.exit(2)

for match in matches:
    name = (
        (match.get("metaVariables") or {})
        .get("single", {})
        .get("NAME", {})
        .get("text", "?")
    )
    line = (match.get("range") or {}).get("start", {}).get("line", 0) + 1
    print(
        f"{match.get('file', '?')}:{line}: "
        f"standalone `pub const {name}: ProblemCode` outside the problem_codes! "
        f"macro — declare it in crates/core/src/error_registry.rs (issue #232)"
    )
PYEOF
if [ "$report_rc" -ne 0 ]; then
    exit "$report_rc"
fi
exit 1  # violations were reported above
