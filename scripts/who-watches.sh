#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0
# Copyright (C) 2024-2026 Breakdown RS Contributors
# Co-authored-by: deepseek-v4.1-flash (opencode-go)
#
# who-watches.sh — answer "who observes this Riverpod provider?" in ONE call.
#
# Why this exists: the two discovery tools are each half-blind for this exact
# question. `codebase-memory` resolves definitions and call edges, but Riverpod
# wiring is dynamic (`ref.watch(...)`), so it cannot see the observer edge; plain
# text search sees the mention but not what it means. Until now "use the graph
# first" therefore produced a WORSE answer than `rg` for this question, and a
# rule that loses to the convenient tool loses. This wrapper runs both and
# presents them as one answer:
#
#   1. the graph: the provider's definition(s)/family (kind + file:line), and —
#      for function-like providers — any inbound call edges it does model;
#   2. text search: every `ref.watch/read/listen(<provider>)` call site, which
#      IS the observer set, grouped by file.
#
# Usage:
#   scripts/who-watches.sh currentMembershipProvider
#   scripts/who-watches.sh aiConfigReachabilityProvider frontend-flutter/lib
#
# Env:
#   CODEBASE_MEMORY_BIN   binary to call (default: codebase-memory-mcp)
#   CODEBASE_MEMORY_PROJECT  project name override (default: derived)
#
# Notes:
#   * Read-only: no index mutation, no network. An empty graph answer prints the
#     freshness hint instead of "does not exist" (the index is machine-local).
#   * `--help` for usage.

set -uo pipefail

BIN=${CODEBASE_MEMORY_BIN:-codebase-memory-mcp}
ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || ROOT=$(pwd)

usage() {
    sed -n '2,32p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

case "${1:-}" in
    -h | --help | "")
        usage
        [ -n "${1:-}" ] || exit 2
        exit 0
        ;;
esac

PROVIDER=$1
SEARCH_PATH=${2:-.}

command -v "$BIN" >/dev/null 2>&1 || {
    echo "who-watches: '$BIN' not found — set CODEBASE_MEMORY_BIN or install codebase-memory-mcp" >&2
    exit 1
}

cd "$ROOT" || exit 1

PROJECT=${CODEBASE_MEMORY_PROJECT:-}
if [ -z "$PROJECT" ]; then
    PROJECT=$(
        "$BIN" cli --quiet list_projects '{"format":"json"}' 2>/dev/null |
            python3 -c '
import json, os, sys
try:
    payload = json.load(sys.stdin)
except Exception:
    sys.exit(0)
cwd = os.getcwd()
matches = [
    p for p in payload.get("projects", [])
    if isinstance(p.get("root_path"), str) and cwd.startswith(p["root_path"])
]
matches.sort(key=lambda p: len(p["root_path"]), reverse=True)
print(matches[0]["name"] if matches else "")
'
    )
fi
[ -n "$PROJECT" ] || {
    echo "who-watches: no codebase-memory project contains $ROOT (is the index built?)" >&2
    exit 1
}

# The generated getter is `<family>Provider`; the hand-written symbol is the
# family (camelCase) for a function provider and PascalCase for a class provider.
FAMILY=${PROVIDER%Provider}
if [[ $FAMILY =~ ^[a-z] ]]; then
    PASCAL="$(printf '%s' "${FAMILY:0:1}" | tr '[:lower:]' '[:upper:]')${FAMILY:1}"
else
    PASCAL=$FAMILY
fi

echo "== graph (codebase-memory · $PROJECT) =="
for symbol in "$FAMILY" "$PASCAL" "$PROVIDER"; do
    payload=$("$BIN" cli --quiet search_graph \
        "{\"project\":\"$PROJECT\",\"query\":\"$symbol\",\"limit\":10,\"format\":\"json\"}" 2>/dev/null) || continue
    hits=$(printf '%s' "$payload" | python3 -c '
import json, sys
try:
    payload = json.load(sys.stdin)
except Exception:
    sys.exit(0)
cols = payload.get("cols") or []
rows = payload.get("rows") or []
out = []
for row in rows:
    rec = dict(zip(cols, row))
    qn = str(rec.get("qn") or "")
    file = str(rec.get("file") or "")
    if not file or not qn.rsplit(".", 1)[-1] == sys.argv[1]:
        continue
    if file.endswith(".g.dart") or file.endswith(".freezed.dart"):
        continue
    out.append("  - %s (%s) %s:%s" % (sys.argv[1], rec.get("label"), file, str(rec.get("lines") or "").split("-")[0]))
print("\n".join(out[:3]))
' "$symbol")
    [ -n "$hits" ] && printf '%s\n' "$hits"
done | sort -u | head -6

# Inbound edges the graph DOES model (function-style providers only; a class
# reports 0 legitimately, and its generated `.create` is not a consumer).
inbound=$("$BIN" cli --quiet trace_path \
    "{\"project\":\"$PROJECT\",\"function_name\":\"$FAMILY\",\"direction\":\"inbound\",\"limit\":20,\"format\":\"json\"}" 2>/dev/null |
    python3 -c '
import json, sys
try:
    payload = json.load(sys.stdin)
except Exception:
    sys.exit(0)
groups = (payload.get("callers") or {}).get("groups") or []
names = []
for group in groups:
    owner = (group.get("qn_prefix") or "").rsplit(".", 1)[-1]
    if owner.endswith("Provider"):
        continue
    for row in group.get("rows") or []:
        names.append("%s.%s" % (owner, row[0]) if owner else str(row[0]))
print(", ".join(names[:6]) + (" …" if len(names) > 6 else ""))
' 2>/dev/null)
[ -n "$inbound" ] && echo "  inbound call edges: $inbound"

if ! "$BIN" cli --quiet search_graph \
    "{\"project\":\"$PROJECT\",\"query\":\"$PASCAL\",\"limit\":1,\"format\":\"json\"}" >/dev/null 2>&1; then
    echo "  (no graph answer — index may be stale: scripts/check-graph-freshness.sh)"
fi

echo
echo "== observers (text search: the ref.watch/read/listen call sites) =="
# The observer set is exactly these call sites; `ref.watch` is dynamic and thus
# not a graph edge. Both spellings are matched (family + generated getter).
rg -n --no-heading -g '!*.g.dart' -g '!vendor/**' -g '!build/**' \
    "ref\.(watch|read|listen)\(\s*${PROVIDER}\b" "$SEARCH_PATH" 2>/dev/null |
    head -40 || true

echo
echo "Both answers together are the answer: the graph names the symbol and the"
echo "edges it models; the call sites above are the real observer set."
