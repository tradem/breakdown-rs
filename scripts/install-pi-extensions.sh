#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0
# Copyright (C) 2024-2026 Breakdown RS Contributors
# Co-authored-by: deepseek-v4.1-flash (opencode-go)
#
# install-pi-extensions.sh — link the repo's pi extensions into the agent's
# GLOBAL extension directory, so they load in EVERY session on this machine.
#
# Why this exists: pi discovers project-local extensions from the session's own
# `.pi/extensions/`, so a session started in `frontend-flutter/` (or `backend/`)
# never sees `breakdown-rs/.pi/extensions/*.ts`. The `graph-first-nudge`
# advisory therefore fired only for sessions started at the monorepo root — and
# the area session is the repo's recommended shape (AGENTS.md §1–2). Global
# extensions (`$AGENT_DIR/extensions/*.ts`) load regardless of cwd and of
# project trust; the extension itself resolves the indexed project from the
# session cwd and appends nothing where no indexed project contains that cwd.
#
# Usage:
#   scripts/install-pi-extensions.sh              # link / refresh
#   scripts/install-pi-extensions.sh --dry-run    # show what would change
#   scripts/install-pi-extensions.sh --uninstall  # remove OUR links only
#
# Notes:
#   * Symlinks, never copies: the repo stays the single source of truth, and a
#     `/reload` in a running pi session picks the edit up immediately.
#   * The agent directory is `$PI_CODING_AGENT_DIR` when set, else
#     `~/.pi/agent` — the same seam the harness documents for its own config.
#   * A non-symlink file already at a target is moved aside to
#     `<name>.bak.<timestamp>`: a hand-written extension is not ours to destroy.
#   * Only `*.ts`/`*.js` files DIRECTLY inside `.pi/extensions/` are linked;
#     vendored subdirectories are left alone (they are not single-file
#     extensions).

set -uo pipefail

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SRC="$ROOT/.pi/extensions"
AGENT_DIR="${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}"
DST="$AGENT_DIR/extensions"
DRY_RUN=0
UNINSTALL=0

for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=1 ;;
        --uninstall) UNINSTALL=1 ;;
        -h | --help)
            sed -n '2,33p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *)
            echo "install-pi-extensions.sh: unknown argument: $arg" >&2
            exit 2
            ;;
    esac
done

if [ ! -d "$SRC" ]; then
    echo "install-pi-extensions.sh: no extension directory at $SRC" >&2
    exit 1
fi

run() {
    if [ "$DRY_RUN" = "1" ]; then
        printf 'would: %s\n' "$*"
    else
        "$@"
    fi
}

echo "repo:  $SRC"
echo "agent: $DST"
[ "$DRY_RUN" = "1" ] && echo "(dry run — nothing is changed)"

changed=0
for ext in "$SRC"/*.ts "$SRC"/*.js; do
    [ -e "$ext" ] || continue
    name=$(basename "$ext")
    target="$DST/$name"

    if [ "$UNINSTALL" = "1" ]; then
        if [ -L "$target" ] && [ "$(readlink -f "$target")" = "$(readlink -f "$ext")" ]; then
            run rm -f "$target"
            echo "removed  $name"
            changed=$((changed + 1))
        elif [ -e "$target" ] || [ -L "$target" ]; then
            echo "kept     $name (not our symlink)"
        fi
        continue
    fi

    if [ -L "$target" ] && [ "$(readlink -f "$target")" = "$(readlink -f "$ext")" ]; then
        echo "ok       $name"
        continue
    fi
    if [ -L "$target" ]; then
        run rm -f "$target"
    elif [ -e "$target" ]; then
        backup="$target.bak.$(date +%Y%m%d%H%M%S)"
        run mv "$target" "$backup"
        echo "moved    $name → $(basename "$backup")"
    fi
    run mkdir -p "$DST"
    run ln -s "$ext" "$target"
    echo "linked   $name → $ext"
    changed=$((changed + 1))
done

if [ "$changed" = "0" ]; then
    echo "nothing to do."
else
    echo "done ($changed change(s))."
    [ "$DRY_RUN" = "1" ] || echo "Reload a RUNNING pi session with /reload; new sessions pick it up automatically."
fi
