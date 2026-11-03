#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0
# Copyright (C) 2024-2026 Breakdown RS Contributors
# Co-authored-by: deepseek-v4.1-flash (opencode-go)
#
# reindex-graph.sh — refresh the local codebase-memory knowledge graph for this
# monorepo (the index covers backend Rust, frontend-flutter Dart, docs, SQL...).
#
# Why this exists: the graph index lives in the gitignored, machine-local
# `.codebase-memory/` and is never rebuilt by CI. codebase-memory auto-syncs
# only the active MCP session's project, and sessions launched in
# `frontend-flutter/` or `backend/` do not qualify for that project (the index
# root is the monorepo root), so "watched" is false and the graph rots silently
# while agents query it. This wrapper is the one canonical way to refresh it —
# used by the git hooks, by the agent-side convention in AGENTS.md, and by
# humans.
#
# Usage:
#   scripts/reindex-graph.sh                    # reindex now (mode: full)
#   scripts/reindex-graph.sh --if-stale         # only when HEAD moved
#   scripts/reindex-graph.sh --mode moderate    # full|moderate|fast
#   scripts/reindex-graph.sh --if-stale --background   # hooks: fire & forget
#
# Env:
#   CODEBASE_MEMORY_BIN     binary to call (default: codebase-memory-mcp)
#   CODEBASE_MEMORY_PROJECT project name override (default: derived by the tool)
#   CODEBASE_MEMORY_SKIP_AUTOINDEX=1  make the hooks a no-op
#
# Notes:
#   * Lock file and log live inside the git directory
#     (`<git-common-dir>/codebase-memory/`) so they can never pollute the
#     worktree or land in a commit.
#   * A held lock means another reindex is running; we skip instead of racing.

set -uo pipefail

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
BIN=${CODEBASE_MEMORY_BIN:-codebase-memory-mcp}

# State (lock + log) belongs to the repository, not the checkout: keep it in the
# git common dir, which git never tracks. `--git-common-dir` may be relative
# (plain repo) or absolute (linked worktree).
GIT_COMMON=$(git -C "$ROOT" rev-parse --git-common-dir 2>/dev/null || echo ".git")
case "$GIT_COMMON" in
    /*) ;;
    *) GIT_COMMON="$ROOT/$GIT_COMMON" ;;
esac
STATE_DIR="$GIT_COMMON/codebase-memory"
LOCK="$STATE_DIR/reindex.lock"
LOG="$STATE_DIR/reindex.log"

MODE="full"
IF_STALE=0
BACKGROUND=0
PERSISTENCE="true"

while [ $# -gt 0 ]; do
    case "$1" in
        --if-stale) IF_STALE=1 ;;
        --background) BACKGROUND=1 ;;
        --mode)
            shift
            [ $# -gt 0 ] || { echo "reindex-graph.sh: --mode needs a value" >&2; exit 64; }
            MODE=$1
            ;;
        --mode=*) MODE=${1#--mode=} ;;
        --no-persistence) PERSISTENCE="false" ;;
        -h | --help)
            sed -n '2,33p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *)
            echo "reindex-graph.sh: unknown argument: $1" >&2
            echo "Try --help." >&2
            exit 64
            ;;
    esac
    shift
done

case "$MODE" in
    full | moderate | fast) ;;
    *)
        echo "reindex-graph.sh: invalid --mode '$MODE' (want full|moderate|fast)" >&2
        exit 64
        ;;
esac

if [ ! -e "$LOCK" ] || [ ! -d "$LOCK" ]; then
    mkdir -p "$STATE_DIR"
    : > "$LOCK"
fi

run_index() {
    local -a cmd=("$BIN" cli --quiet index_repository --repo-path "$ROOT" --mode "$MODE" --persistence "$PERSISTENCE")
    if [ -n "${CODEBASE_MEMORY_PROJECT:-}" ]; then
        cmd+=(--name "$CODEBASE_MEMORY_PROJECT")
    fi
    "${cmd[@]}"
}

if [ "$BACKGROUND" -eq 1 ]; then
    # Re-exec detached: the hook must return immediately (a post-merge hook that
    # blocks on a 30k-node reindex would be unusable).
    if [ "${CODEBASE_MEMORY_SKIP_AUTOINDEX:-0}" = "1" ]; then
        exit 0
    fi
    if ! command -v "$BIN" >/dev/null 2>&1; then
        exit 0
    fi
    child_arg=""
    [ "$IF_STALE" -eq 1 ] && child_arg="--if-stale"
    nohup bash "${BASH_SOURCE[0]}" --mode "$MODE" $child_arg >>"$LOG" 2>&1 </dev/null &
    echo "graph reindex started in the background (log: $LOG)"
    exit 0
fi

echo "[$(date -Is)] reindex-graph: start (mode=$MODE root=$ROOT)" >>"$LOG"

if ! command -v "$BIN" >/dev/null 2>&1; then
    echo "reindex-graph.sh: '$BIN' not found on PATH." >&2
    echo "Install codebase-memory-mcp or set CODEBASE_MEMORY_BIN." >&2
    exit 69
fi

if [ "$IF_STALE" -eq 1 ]; then
    bash "$ROOT/scripts/check-graph-freshness.sh" --quiet
    rc=$?
    if [ "$rc" -eq 0 ]; then
        echo "[$(date -Is)] reindex-graph: index already fresh, nothing to do" >>"$LOG"
        echo "graph index is fresh at HEAD — nothing to do."
        exit 0
    fi
fi

exec 9>"$LOCK"
if ! flock -n 9; then
    echo "another reindex is already running ($LOCK held) — skipping." >&2
    echo "[$(date -Is)] reindex-graph: lock busy, skipped" >>"$LOG"
    exit 0
fi

echo "reindexing knowledge graph ($MODE) — this can take a few minutes…"
run_index >>"$LOG" 2>&1
rc=$?

if [ "$rc" -ne 0 ]; then
    echo "[$(date -Is)] reindex-graph: FAILED (rc=$rc, see $LOG)" >>"$LOG"
    echo "reindex failed (rc=$rc). Last log lines ($LOG):" >&2
    tail -n 20 "$LOG" >&2
    exit "$rc"
fi

echo "[$(date -Is)] reindex-graph: done" >>"$LOG"
bash "$ROOT/scripts/check-graph-freshness.sh" || true
