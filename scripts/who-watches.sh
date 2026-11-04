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

# Comment-aware filter for `rg --json -U` match records.
#
# The old approach parsed `rg -n --no-heading` text: it split the header on the
# first colon (so a path containing `:` desynchronised the drop state), it
# carried a drop flag from one match to the next (so a commented match could
# hide a real call site and vice versa), and it could only inspect the matched
# line (so a call on a later line of a `/* … */` block passed, while a `//`
# inside a string literal on the same line dropped a live call).
#
# Structured records fix the parsing; reading the FILE fixes the comment
# question: a small Dart-aware scanner replays the file up to the match offset
# and tracks `//`, `/* */` (nestable) and single/triple-quoted string literals,
# so "is this call site commented out" is answered by real state, not by a
# substring search on one line. Each kept match prints as `path:line:text`
# (continuation lines of a multiline match are indented), capped at the count
# given as the first argument.
COMMENT_FILTER_PY=$(
    cat <<'PY'
import json, sys

limit = int(sys.argv[1]) if len(sys.argv) > 1 else 0

def in_comment(src, offset):
    """True when `offset` sits inside a `//` or `/* */` comment."""
    i = 0
    n = min(offset, len(src))
    state = None  # None | "line" | "block" | the string delimiter
    depth = 0
    while i < n:
        c = src[i:i + 1]
        if state is None:
            if c == b"/" and src[i + 1:i + 2] == b"/":
                state = "line"
                i += 2
                continue
            if c == b"/" and src[i + 1:i + 2] == b"*":
                state = "block"
                depth = 1
                i += 2
                continue
            if c in (b"'", b'"'):
                if src[i:i + 3] == c * 3:
                    state = c * 3
                    i += 3
                    continue
                state = c
                i += 1
                continue
            i += 1
            continue
        if state == "line":
            if c == b"\n":
                state = None
            i += 1
            continue
        if state == "block":
            if c == b"/" and src[i + 1:i + 2] == b"*":
                depth += 1
                i += 2
                continue
            if c == b"*" and src[i + 1:i + 2] == b"/":
                depth -= 1
                i += 2
                if depth == 0:
                    state = None
                continue
            i += 1
            continue
        # Inside a string literal.
        if c == b"\\" and len(state) == 1:
            i += 2
            continue
        if src[i:i + len(state)] == state:
            i += len(state)
            state = None
            continue
        i += 1
    return state in ("line", "block")

cache = {}
kept = 0
for raw in sys.stdin:
    raw = raw.strip()
    if not raw:
        continue
    try:
        record = json.loads(raw)
    except ValueError:
        continue
    if record.get("type") != "match":
        continue
    data = record.get("data") or {}
    path = (data.get("path") or {}).get("text") or ""
    offset = data.get("absolute_offset") or 0
    # `absolute_offset` is where `lines.text` STARTS; the call site is at the
    # first submatch inside it. Using the line start alone would test the
    # comment state at the wrong byte (`// ref.watch(…)` has a 3-byte prefix).
    submatches = data.get("submatches") or []
    if submatches:
        offset += submatches[0].get("start") or 0
    line_number = data.get("line_number") or 0
    text = ((data.get("lines") or {}).get("text") or "").rstrip("\n")
    if not path:
        continue
    if path not in cache:
        try:
            with open(path, "rb") as handle:
                cache[path] = handle.read()
        except OSError:
            cache[path] = None
    source = cache[path]
    if source is not None and in_comment(source, offset):
        continue
    first, _, rest = text.partition("\n")
    print("%s:%s:%s" % (path, line_number, first.strip()))
    for line in rest.splitlines():
        if line.strip():
            print("  " + line.strip())
    kept += 1
    if limit and kept >= limit:
        break
PY
)

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
def contains(directory, root):
    # Path-COMPONENT boundary: /work/app must not match an indexed /work/ap.
    root = root.rstrip("/")
    return directory == root or directory.startswith(root + "/")

matches = [
    p for p in payload.get("projects", [])
    if isinstance(p.get("root_path"), str) and contains(cwd, p["root_path"])
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
# Lookup failures must survive the `$( )` substitution below, otherwise "the
# lookup did not complete" would be reported as "no definition exists".
FAILED_LOOKUPS=$(mktemp)
trap 'rm -f "$FAILED_LOOKUPS"' EXIT
graph_lines=$(
for symbol in "$FAMILY" "$PASCAL" "$PROVIDER"; do
    payload=$("$BIN" cli --quiet search_graph \
        "{\"project\":\"$PROJECT\",\"query\":\"$symbol\",\"limit\":40,\"format\":\"json\"}" 2>/dev/null) || {
        printf '%s\n' "$symbol" >>"$FAILED_LOOKUPS"
        continue
    }
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
)
failed=$(sort -u "$FAILED_LOOKUPS" 2>/dev/null | tr '\n' ' ')
if [ -n "$graph_lines" ]; then
    printf '%s\n' "$graph_lines"
    [ -n "$failed" ] && echo "  (lookup failed for: ${failed% } — cross-check manually)"
elif [ -n "$failed" ]; then
    # A FAILED lookup is not an empty index.
    echo "  (lookup failed for: ${failed% } — the index may be stale or the CLI"
    echo "   unavailable; run scripts/check-graph-freshness.sh before concluding"
    echo "   that no such symbol exists)"
else
    # An empty section must say WHY: "no definition named X" and "stale index"
    # look identical otherwise, and that ambiguity is what makes the graph feel
    # broken (see AGENTS.md §2).
    echo "  (no definition named ${FAMILY} / ${PASCAL} — try the hand-written family"
    echo "   name, or check freshness: scripts/check-graph-freshness.sh)"
fi

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

echo
echo "== observers (ref.watch / ref.listen — these SUBSCRIBE) =="
# The observer set is exactly these call sites; `ref.watch` is dynamic and thus
# not a graph edge. `-U` so a provider name on the NEXT line still matches
# (multiline Riverpod calls). Both spellings are matched (family + getter).
# Comment matches are dropped by COMMENT_FILTER_PY: a `///` doc comment or a
# trailing `// …` that merely MENTIONS the provider is not a subscription, and
# the section header says "these SUBSCRIBE".
rg --json -U -g '!*.g.dart' -g '!vendor/**' -g '!build/**' \
    "ref\.(watch|listen)\(\s*${PROVIDER}\b" "$SEARCH_PATH" 2>/dev/null |
    python3 -c "$COMMENT_FILTER_PY" 40 || true

echo
echo "== non-subscribing accesses (ref.read — NOT observers) =="
# `ref.read` touches the provider once and does not rebuild on change, so it is
# an access site, not an observer. Listed separately on purpose.
rg --json -U -g '!*.g.dart' -g '!vendor/**' -g '!build/**' \
    "ref\.read\(\s*${PROVIDER}\b" "$SEARCH_PATH" 2>/dev/null |
    python3 -c "$COMMENT_FILTER_PY" 20 || true

echo
echo "Both answers together are the answer: the graph names the symbol and the"
echo "edges it models; the ref.watch/ref.listen call sites above are the observer"
echo "set, the ref.read lines are one-shot accesses."
