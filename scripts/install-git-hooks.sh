#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0
# Copyright (C) 2024-2026 Breakdown RS Contributors
# Co-authored-by: deepseek-v4.1-flash (opencode-go)
#
# install-git-hooks.sh — link every hook in the repo's hooks directory into
# `.git/hooks/`.
#
# Why this exists: the monorepo keeps its hooks in `backend/git-hooks/` (a
# historical name — the directory now carries repo-wide hooks such as the
# codebase-memory refresh on merge/checkout). A file dropped into that
# directory does nothing until it is linked into `.git/hooks/`, and `.git/` is
# never committed — so without this script every contributor silently lacks the
# hook and nobody notices. Idempotent: re-running refreshes existing links.
#
# Usage:
#   scripts/install-git-hooks.sh            # link / refresh all hooks
#   scripts/install-git-hooks.sh --dry-run  # show what would change
#
# Note: if `core.hooksPath` is set, git ignores `.git/hooks/` entirely — this
# script refuses to link in that case instead of pretending to work.

set -uo pipefail

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
HOOKS_SRC="$ROOT/backend/git-hooks"
HOOKS_DST="$ROOT/.git/hooks"
DRY_RUN=0

for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=1 ;;
        -h | --help)
            sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *)
            echo "install-git-hooks.sh: unknown argument: $arg" >&2
            exit 64
            ;;
    esac
done

if ! git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; then
    echo "install-git-hooks.sh: $ROOT is not a git worktree" >&2
    exit 69
fi

HOOKS_PATH=$(git -C "$ROOT" config --get core.hooksPath || true)
if [ -n "$HOOKS_PATH" ]; then
    # A relative core.hooksPath is resolved against the worktree root.
    case "$HOOKS_PATH" in
        /*) resolved="$HOOKS_PATH" ;;
        *) resolved="$ROOT/$HOOKS_PATH" ;;
    esac
    if [ "$(cd "$resolved" 2>/dev/null && pwd -P)" = "$(cd "$HOOKS_SRC" && pwd -P)" ]; then
        echo "git hooks are already active via core.hooksPath = $HOOKS_PATH"
        echo "(files in that directory run directly — nothing to link)"
        ls -1 "$HOOKS_SRC" | sed 's/^/  /'
        exit 0
    fi
    echo "install-git-hooks.sh: core.hooksPath is set to '$HOOKS_PATH'." >&2
    echo "Git ignores .git/hooks in that case — put the hooks in '$resolved' instead." >&2
    exit 69
fi

if [ ! -d "$HOOKS_SRC" ]; then
    echo "install-git-hooks.sh: hooks directory not found: $HOOKS_SRC" >&2
    exit 66
fi

mkdir -p "$HOOKS_DST"
installed=0

for src in "$HOOKS_SRC"/*; do
    [ -f "$src" ] || continue
    name=$(basename "$src")
    case "$name" in
        *.md | *.txt | README*) continue ;;
    esac
    target="$HOOKS_DST/$name"

    if [ -L "$target" ] && [ "$(readlink "$target")" = "../../backend/git-hooks/$name" ]; then
        echo "  ok      $name"
        continue
    fi

    if [ "$DRY_RUN" -eq 1 ]; then
        echo "  link    $name -> ../../backend/git-hooks/$name"
        installed=$((installed + 1))
        continue
    fi

    rm -f "$target"
    # Two levels up from .git/hooks/ is the worktree root.
    ln -sf "../../backend/git-hooks/$name" "$target"
    chmod +x "$src" 2>/dev/null || true
    echo "  linked  $name -> ../../backend/git-hooks/$name"
    installed=$((installed + 1))
done

if [ "$DRY_RUN" -eq 1 ]; then
    echo "dry-run: $installed hook(s) would be linked."
else
    echo "done: $installed hook(s) linked into .git/hooks/."
fi
