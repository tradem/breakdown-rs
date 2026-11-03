#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0
# Copyright (C) 2024-2026 Breakdown RS Contributors
# Co-authored-by: deepseek-v4.1-flash (opencode-go)
#
# check-graph-freshness.sh — report how far the local codebase-memory graph
# index lags behind HEAD.
#
# Why this exists: `.codebase-memory/` is gitignored and machine-local, so the
# knowledge-graph index is NOT covered by CI and cannot be. It silently rots
# between explicit reindexes (`index_status` reports `watch: watched=false` for
# sessions launched below the monorepo root). A stale index answers "no such
# symbol" for code that exists on disk, which is exactly how an agent learns to
# distrust the graph and fall back to grep. This script makes the staleness
# visible before it costs a lookup.
#
# Usage:
#   scripts/check-graph-freshness.sh              # human-readable report
#   scripts/check-graph-freshness.sh --quiet      # exit code only
#   scripts/check-graph-freshness.sh --assert     # exit 1 when stale
#
# Exit codes (all modes except the default report, which is informational):
#   0  index is at HEAD (or no index exists — nothing to be stale)
#   1  index is behind HEAD
#   2  no index present
#
# `--quiet` and `--assert` are equivalent for exit purposes: both make
# staleness visible to a caller (`reindex-graph.sh --if-stale` relies on it).
# The default report mode always exits 0 so a human shell is not tripped up by
# an informational command.
#
# Overridable via env:
#   CODEBASE_MEMORY_ARTIFACT  path to artifact.json (default: repo root copy)
#   GRAPH_FRESHNESS_CODE_EXTS  extensions that count as "code" for the summary

set -uo pipefail

MODE="report"

for arg in "$@"; do
    case "$arg" in
        --quiet) MODE="quiet" ;;
        --assert) MODE="assert" ;;
        -h | --help)
            sed -n '2,38p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *)
            echo "check-graph-freshness.sh: unknown argument: $arg" >&2
            echo "Try --help." >&2
            exit 64
            ;;
    esac
done

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
ARTIFACT=${CODEBASE_MEMORY_ARTIFACT:-"$ROOT/.codebase-memory/artifact.json"}
CODE_EXTS=${GRAPH_FRESHNESS_CODE_EXTS:-"dart rs sql py kt hcl"}
CODE_REGEX="\\.("$(printf '%s' "$CODE_EXTS" | tr ' ' '|')")$"

emit() {
    [ "$MODE" = "quiet" ] || printf '%s\n' "$*"
}

if [ ! -f "$ARTIFACT" ]; then
    emit "graph index: none ($ARTIFACT missing)"
    emit "status:      NO INDEX — run scripts/reindex-graph.sh"
    [ "$MODE" = "quiet" ] || exit 0
    exit 2
fi

# artifact.json is a flat JSON object written by the indexer; a tiny sed
# extraction avoids a hard jq dependency for a hook that must never fail hard.
field() {
    sed -n 's/.*"'"$1"'"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$ARTIFACT" | head -n 1
}

INDEXED_COMMIT=$(field commit)
INDEXED_AT=$(field indexed_at)

if [ -z "$INDEXED_COMMIT" ]; then
    emit "graph index: unreadable artifact ($ARTIFACT)"
    emit "status:      UNKNOWN — run scripts/reindex-graph.sh"
    [ "$MODE" = "quiet" ] || exit 0
    exit 2
fi

HEAD_COMMIT=$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || echo "")

if [ -z "$HEAD_COMMIT" ]; then
    emit "graph index: commit ${INDEXED_COMMIT:0:7} ($INDEXED_AT)"
    emit "status:      UNKNOWN (not a git checkout) — cannot compare"
    exit 0
fi

if [ "$INDEXED_COMMIT" = "$HEAD_COMMIT" ]; then
    emit "graph index: commit ${INDEXED_COMMIT:0:7} ($INDEXED_AT)"
    emit "HEAD:        ${HEAD_COMMIT:0:7}"
    emit "status:      FRESH"
    exit 0
fi

if ! git -C "$ROOT" cat-file -e "${INDEXED_COMMIT}^{commit}" 2>/dev/null; then
    emit "graph index: commit ${INDEXED_COMMIT:0:7} ($INDEXED_AT)"
    emit "HEAD:        ${HEAD_COMMIT:0:7}"
    emit "status:      STALE — indexed commit is unreachable (rebase/GC); run scripts/reindex-graph.sh"
    [ "$MODE" = "report" ] && exit 0
    exit 1
fi

BEHIND=$(git -C "$ROOT" rev-list --count "$INDEXED_COMMIT..$HEAD_COMMIT" 2>/dev/null || echo "?")
CHANGED=$(git -C "$ROOT" diff --name-only "$INDEXED_COMMIT..$HEAD_COMMIT" 2>/dev/null || true)
CHANGED_TOTAL=$(printf '%s\n' "$CHANGED" | grep -c . || true)
CHANGED_CODE=$(printf '%s\n' "$CHANGED" | grep -E "$CODE_REGEX" | wc -l | tr -d ' ')

emit "graph index: commit ${INDEXED_COMMIT:0:7} ($INDEXED_AT)"
emit "HEAD:        ${HEAD_COMMIT:0:7}"
emit "behind:      $BEHIND commit(s); $CHANGED_TOTAL file(s) changed, $CHANGED_CODE of them code"

if [ "$MODE" != "quiet" ] && [ "${CHANGED_CODE:-0}" -gt 0 ]; then
    printf '%s\n' "$CHANGED" | grep -E "$CODE_REGEX" | sed 's/^/  /' | head -n 8
    if [ "$CHANGED_CODE" -gt 8 ]; then
        echo "  … and $((CHANGED_CODE - 8)) more"
    fi
fi

emit "status:      STALE — symbols from those files may be missing from the graph;"
emit "             run scripts/reindex-graph.sh (or 'index_repository' from a session)"

if [ "$MODE" = "report" ]; then
    exit 0
fi
exit 1
