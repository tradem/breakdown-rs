#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0
# Copyright (C) 2024-2026 Breakdown RS Contributors
# Co-authored-by: muse-spark-1.3-contributor-free (opencode)
# Co-authored-by: deepseek-v4.1-flash (opencode-go)
# add-spdx-headers.sh - add, or verify, SPDX license headers (issue #814)
#
# Usage:
#   ./add-spdx-headers.sh [--apply] [path ...]   add headers (default; idempotent)
#   ./add-spdx-headers.sh --check [path ...]     verify only, exit 1 on offenders
#   ./add-spdx-headers.sh --dry-run [path ...]   list what would change, exit 0
#
# A `path` may be a directory (recursed) or a single file (evaluated directly).
# Defaults to `.` when no path is given, so `--check` in CI is just
# `bash scripts/add-spdx-headers.sh --check`.
#
# The header rule itself is normative in `AGENTS.md` §2 ("License") /
# `backend/AGENTS.md` §7 / `frontend-flutter/AGENTS.md` §10. The skip list below
# is DESCRIPTIVE: it names the trees that tooling reproduces byte-for-byte or
# that are frozen history, where an injected header would be stripped by the
# next regeneration (or rewrite history) instead of helping.
#
# Skip list (rebuild-only artifacts, issue #345; extended by issue #814):
#   - backend/openapi.yaml: written verbatim by
#     `UPDATE_OPENAPI=1 cargo test -p api --test contract openapi_drift`; any
#     header makes the artifact differ from the generated document. Scoped to
#     `backend/` so a hand-authored openapi.yaml elsewhere still gains a header.
#   - frontend-flutter/vendor/**: committed output of scripts/regen-client.sh;
#     a header makes the committed tree differ from the regenerated tree and
#     fails the `openapi-client-drift` CI job.
#   - frontend-flutter/lib/l10n/generated/**: output of `flutter gen-l10n`; a
#     header breaks the gen-l10n drift gate (there is no way to make the
#     generator emit it).
#   - backend/rules-tests/__snapshots__/**: ast-grep snapshot suite output,
#     rewritten on `--update-snapshots`; a header would make every snapshot
#     diff and change the matched offsets.
#   - openspec/changes/archive/**: frozen governance history. Retrofitting an
#     archived change rewrites what was actually decided at the time; the
#     living artifacts (`openspec/specs/**`, active changes) do carry headers.
#   - *.g.dart / *.freezed.dart / *.mocks.dart and **/.dart_tool/**: output of
#     `dart run build_runner build`; the next run strips the header again,
#     causing endless diff churn and possible `dart format` failures.
# Complementing the path-level prune, a content-level guard skips any file
# whose first line matches "GENERATED", so a future generated tree is covered
# even if nobody updates the path list.

set -euo pipefail

LICENSE="AGPL-3.0"
COPYRIGHT="Copyright (C) 2024 Breakdown RS Contributors"
YEAR=$(date +%Y)

# If year differs from 2024, use range
if [ "$YEAR" != "2024" ]; then
    COPYRIGHT="Copyright (C) 2024-$YEAR Breakdown RS Contributors"
fi

MODE="apply"
SEARCH_PATHS=()

for arg in "$@"; do
    case "$arg" in
        --check)   MODE="check" ;;
        --dry-run) MODE="dry-run" ;;
        --apply)   MODE="apply" ;;
        -h|--help) sed -n '5,12p' "$0"; exit 0 ;;
        -*)        echo "❌ Unknown option: $arg" >&2; exit 2 ;;
        *)         SEARCH_PATHS+=("$arg") ;;
    esac
done

if [ "${#SEARCH_PATHS[@]}" -eq 0 ]; then
    SEARCH_PATHS=(".")
fi

# A path that does not exist is a caller bug (a stale list, a wrong working
# directory). Failing loudly matters most in `--check`: the pre-commit hook
# passes repo-root-relative paths, and a silent skip would turn a mis-rooted
# invocation into a vacuous pass.
for p in "${SEARCH_PATHS[@]}"; do
    if [ ! -e "$p" ]; then
        echo "❌ No such file or directory: $p (run from the path's root)" >&2
        exit 2
    fi
done

# --- Skip list -------------------------------------------------------------
# Single source of truth for every mode. Returns a short reason on stdout when
# the path is exempt, nothing when it must carry a header. Operates on the
# normalized path so it works for both `find` output and explicit file args.
skip_reason() {
    local path="$1"
    # Normalize "./" and any absolute prefix so the predicates are path-shape
    # stable regardless of how the caller spelled the path.
    local rel="${path#./}"
    case "$rel" in
        */.git/*|.git/*)                     echo "git metadata"; return 0 ;;
        */node_modules/*|node_modules/*)     echo "node_modules"; return 0 ;;
        */.dart_tool/*|.dart_tool/*)         echo "build_runner output"; return 0 ;;
        */build/*|build/*)                   echo "build output"; return 0 ;;
        */target/*|target/*)                 echo "cargo target dir"; return 0 ;;
        */frontend-flutter/vendor/*|frontend-flutter/vendor/*)
                                             echo "generated OpenAPI client"; return 0 ;;
        */frontend-flutter/lib/l10n/generated/*|frontend-flutter/lib/l10n/generated/*)
                                             echo "gen-l10n output"; return 0 ;;
        */backend/rules-tests/__snapshots__/*|backend/rules-tests/__snapshots__/*)
                                             echo "ast-grep snapshot"; return 0 ;;
        */openspec/changes/archive/*|openspec/changes/archive/*)
                                             echo "frozen governance history"; return 0 ;;
        */backend/openapi.yaml|backend/openapi.yaml)
                                             echo "utoipa-generated contract"; return 0 ;;
        *.g.dart|*.freezed.dart|*.mocks.dart) echo "build_runner output"; return 0 ;;
    esac
    return 1
}

# Header-carrier predicate: the SPDX line is the marker every mode agrees on.
has_header() {
    grep -q "SPDX-License-Identifier" "$1"
}

# Returns the header block for a file, terminator included, without the blank
# separation line. Comment syntax follows the file extension.
header_block() {
    local file="$1"
    case "$file" in
        *.rs|*.typ|*.dart)
            printf '// SPDX-License-Identifier: %s\n// %s\n' "$LICENSE" "$COPYRIGHT"
            ;;
        *.sh|*.feature|*.yaml|*.yml)
            printf '# SPDX-License-Identifier: %s\n# %s\n' "$LICENSE" "$COPYRIGHT"
            ;;
        *.md)
            printf '<!-- SPDX-License-Identifier: %s -->\n<!-- %s -->\n' "$LICENSE" "$COPYRIGHT"
            ;;
        *)
            return 1
            ;;
    esac
}

# Collect candidate files. Directories are recursed; explicit files are taken
# as given (so a pre-commit hook can pass a staged list). The extension filter
# mirrors the header rule: `.rs .typ .sh .dart .feature .yaml .yml .md`.
collect_files() {
    local p
    for p in "$@"; do
        if [ -d "$p" ]; then
            find "$p" -type f \
                \( -name "*.rs" -o -name "*.typ" -o -name "*.sh" \
                   -o -name "*.dart" -o -name "*.feature" \
                   -o -name "*.yaml" -o -name "*.yml" \
                   -o -name "*.md" \) \
                -not -path "*/.git/*" \
                -not -path "*/node_modules/*" \
                -print
        elif [ -f "$p" ]; then
            case "$p" in
                *.rs|*.typ|*.sh|*.dart|*.feature|*.yaml|*.yml|*.md) printf '%s\n' "$p" ;;
            esac
        else
            echo "⚠️  Not a file or directory: $p" >&2
        fi
    done
}

# Write `header` above `file`, preserving a shebang and Markdown frontmatter.
apply_header() {
    local file="$1"
    local header="$2"
    local temp_file
    local insert_at=0   # number of leading lines to keep above the header
    local separator=""  # newline emitted between the kept lines and the header

    temp_file=$(mktemp)

    # A shell script's `#!` interpreter line must stay line 1, otherwise the
    # kernel refuses to exec it (found by the #814 retrofit: every hand-written
    # script in this repo has the shebang first and the header directly below,
    # with no blank line between them).
    if IFS= read -r first_line < "$file" && [ "${first_line:0:2}" = "#!" ]; then
        insert_at=1
    fi

    # Markdown may start with YAML frontmatter (e.g. pi-rules
    # `.github/instructions` rule files); the header MUST go after the closing
    # `---`, or downstream tools would read the frontmatter as body text and the
    # rule file would silently stop matching.
    local skip_blank=0
    if [ "$insert_at" -eq 0 ] && [ "${file##*.}" = "md" ]; then
        if [ "$(head -n 1 "$file")" = "---" ]; then
            local frontmatter_end
            frontmatter_end=$(awk 'NR > 1 && $0 == "---" { print NR; exit }' "$file")
            insert_at=${frontmatter_end:-0}
            separator=$'\n'
            # The body usually already opens with a blank line; consume it so
            # the refused double blank does not appear under the header.
            if [ "$insert_at" -gt 0 ] && \
               [ -z "$(sed -n "$((insert_at + 1))p" "$file")" ]; then
                skip_blank=1
            fi
        fi
    fi

    if [ "$insert_at" -gt 0 ]; then
        head -n "$insert_at" "$file" > "$temp_file"
        printf '%s' "$separator" >> "$temp_file"
    else
        : > "$temp_file"
    fi

    printf '%s\n\n' "$header" >> "$temp_file"

    if [ "$insert_at" -gt 0 ]; then
        tail -n +$((insert_at + 1 + skip_blank)) "$file" >> "$temp_file"
    else
        cat "$file" >> "$temp_file"
    fi

    mv "$temp_file" "$file"
}

# --- Main loop -------------------------------------------------------------
offenders=()
added=0

while IFS= read -r file; do
    [ -n "$file" ] || continue

    if reason=$(skip_reason "$file"); then
        if [ "$MODE" = "apply" ]; then
            echo "⏭️  Skipping ($reason): ${file#./}"
        fi
        continue
    fi

    # Rebuild-only files carry their own banner and are reproduced verbatim by
    # tooling; the path list above covers the known trees, this content-level
    # guard covers any future generated tree regardless of path (issue #345).
    if head -n 1 "$file" | grep -q "GENERATED"; then
        if [ "$MODE" = "apply" ]; then
            echo "⏭️  Skipping (generated file): ${file#./}"
        fi
        continue
    fi

    if has_header "$file"; then
        if [ "$MODE" = "apply" ]; then
            echo "⏭️  Skipping (already has header): ${file#./}"
        fi
        continue
    fi

    header=$(header_block "$file") || {
        echo "⚠️  Unsupported file type: ${file#./}" >&2
        continue
    }

    case "$MODE" in
        check)
            offenders+=("${file#./}")
            ;;
        dry-run)
            offenders+=("${file#./}")
            echo "➕ Would add header to: ${file#./}"
            ;;
        apply)
            apply_header "$file" "$header"
            added=$((added + 1))
            echo "✅ Added header to: ${file#./}"
            ;;
    esac
done < <(collect_files "${SEARCH_PATHS[@]}")

echo ""

case "$MODE" in
    check)
        if [ "${#offenders[@]}" -gt 0 ]; then
            echo "❌ ${#offenders[@]} file(s) missing an SPDX header:" >&2
            printf '   %s\n' "${offenders[@]}" >&2
            echo "" >&2
            echo "Fix with: bash scripts/add-spdx-headers.sh ${SEARCH_PATHS[*]}" >&2
            echo "Or, if the file is a regenerated/frozen artifact, add it to the" >&2
            echo "skip list in scripts/add-spdx-headers.sh (issue #814)." >&2
            exit 1
        fi
        echo "✅ All checked files carry an SPDX header."
        exit 0
        ;;
    dry-run)
        if [ "${#offenders[@]}" -gt 0 ]; then
            echo "ℹ️  ${#offenders[@]} file(s) would gain a header (nothing was written)."
        else
            echo "✅ Nothing to do — every checked file already carries a header."
        fi
        exit 0
        ;;
    apply)
        echo "✅ Done! Added SPDX headers to $added file(s)."
        echo "📋 License: $LICENSE"
        echo "📋 Copyright: $COPYRIGHT"
        ;;
esac
