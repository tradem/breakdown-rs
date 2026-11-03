#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0
# Copyright (C) 2024-2026 Breakdown RS Contributors
# Co-authored-by: deepseek-v4.1-flash (opencode-go)
#
# install-git-hooks.sh — link every hook in the repo's hooks directory into the
# directory git actually reads.
#
# Why this exists: the monorepo keeps its hooks in `backend/git-hooks/` (a
# historical name — the directory now carries repo-wide hooks such as the
# codebase-memory refresh on merge/checkout/rebase). A file dropped into that
# directory does nothing until it is linked into the hooks directory, and the
# git directory is never committed — so without this script every contributor
# silently lacks the hooks and nobody notices. Idempotent: re-running refreshes
# existing links.
#
# Usage:
#   scripts/install-git-hooks.sh            # link / refresh all hooks
#   scripts/install-git-hooks.sh --dry-run  # show what would change
#
# Notes:
#   * If `core.hooksPath` already points at `backend/git-hooks`, the hooks run
#     directly and there is nothing to link — the script says so and exits 0.
#   * The hooks directory is resolved with `git rev-parse --git-path hooks`, not
#     `$ROOT/.git/hooks`: in a linked worktree `$ROOT/.git` is a *file* and git
#     keeps hooks in the common directory.
#   * An existing file at the target that is not one of our symlinks is moved
#     aside to `<name>.bak.<timestamp>` instead of being deleted — a
#     contributor's hand-written hook is not ours to destroy.

set -uo pipefail

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
HOOKS_SRC="$ROOT/backend/git-hooks"
DRY_RUN=0

for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=1 ;;
        -h | --help)
            sed -n '2,29p' "$0" | sed 's/^# \{0,1\}//'
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

if [ ! -d "$HOOKS_SRC" ]; then
    echo "install-git-hooks.sh: hooks directory not found: $HOOKS_SRC" >&2
    exit 66
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
    echo "Git ignores the default hooks directory in that case — put the hooks in '$resolved' instead." >&2
    exit 69
fi

# `--git-path hooks` is worktree-correct and may be relative to $ROOT.
HOOKS_DST=$(git -C "$ROOT" rev-parse --git-path hooks)
case "$HOOKS_DST" in
    /*) ;;
    *) HOOKS_DST="$ROOT/$HOOKS_DST" ;;
esac

if [ "$DRY_RUN" -eq 0 ]; then
    if ! mkdir -p "$HOOKS_DST"; then
        echo "install-git-hooks.sh: cannot create hooks directory: $HOOKS_DST" >&2
        exit 73
    fi
fi

# Prefer a relative link (survives moving the checkout); fall back to an
# absolute one when `realpath --relative-to` is unavailable (BSD/macOS).
rel_link() {
    local target_dir=$1 src=$2 rel
    rel=$(realpath --relative-to="$target_dir" "$src" 2>/dev/null || true)
    if [ -n "$rel" ]; then
        printf '%s\n' "$rel"
    else
        printf '%s\n' "$src"
    fi
}

installed=0

for src in "$HOOKS_SRC"/*; do
    [ -f "$src" ] || continue
    name=$(basename "$src")
    case "$name" in
        *.md | *.txt | README*) continue ;;
    esac
    target="$HOOKS_DST/$name"
    link=$(rel_link "$HOOKS_DST" "$src")

    if [ -L "$target" ] && [ "$(readlink "$target")" = "$link" ]; then
        echo "  ok      $name"
        continue
    fi

    # Anything already there that is not our link belongs to the contributor.
    backup=""
    if [ -e "$target" ] || [ -L "$target" ]; then
        if [ "$DRY_RUN" -eq 1 ]; then
            echo "  backup  $name -> $name.bak.<timestamp> (existing file is not our link)"
            echo "  link    $name -> $link"
            installed=$((installed + 1))
            continue
        fi
        backup="$target.bak.$(date +%Y%m%d%H%M%S)"
        if ! mv -f "$target" "$backup"; then
            echo "install-git-hooks.sh: cannot move '$target' aside — skipping $name" >&2
            continue
        fi
        echo "  backup  $name -> $(basename "$backup")"
    fi

    if [ "$DRY_RUN" -eq 1 ]; then
        echo "  link    $name -> $link"
        installed=$((installed + 1))
        continue
    fi

    if ! ln -s "$link" "$target"; then
        echo "install-git-hooks.sh: cannot link '$target'" >&2
        [ -n "$backup" ] && mv -f "$backup" "$target"
        continue
    fi
    chmod +x "$src" 2>/dev/null || true
    echo "  linked  $name -> $link"
    installed=$((installed + 1))
done

if [ "$DRY_RUN" -eq 1 ]; then
    echo "dry-run: $installed hook(s) would be linked (nothing written)."
else
    echo "done: $installed hook(s) linked into $HOOKS_DST."
fi
