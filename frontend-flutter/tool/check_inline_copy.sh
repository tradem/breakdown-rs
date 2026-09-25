#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0
# Copyright (C) 2024-2026 Breakdown RS Contributors
# Co-authored-by: space-bunny-free (opencode)
#
# Static gate for Issue #518: no user-facing inline copy may remain in
# `lib/features/**`. Every visible string must come from the ARB catalogs via
# `AppLocalizations` / `l10nOf(context)`.
#
# The scan is intentionally narrow (a precision-first gate, not a broad
# string-literal sweep): it only reports string literals passed to the
# user-visible widget parameters below. Everything else in a Dart file —
# keys, log messages, problem `code`s, `ProblemError.title` diagnostics,
# URLs, format patterns, enum wire names — is either technical or not
# rendered, and is allowlisted here by category rather than by path so new
# screens cannot silently widen the surface.
#
# Allowlisted categories (each is a NON-user-facing or server-owned string):
#
#   1. Key(...) / test identifiers ......... widget/test keys, not copy
#   2. Semantics/debug labels ............... diagnostics + `debugLabel`
#   3. URLs / hostnames / endpoints ........... technical connection data
#   4. Problem `code`s and `title:` metadata .. diagnostics; UI branches on
#      the stable `code` and renders localized catalog copy
#   5. Number/date interpolation ............. formatted data, not copy
#   6. Punctuation-only values ................ em dash / ellipsis
#
# Exit code 1 = at least one genuine user-facing literal found.

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root/frontend-flutter"

# Widget parameters that render user-visible text.
#
# NOTE: a bare `title:` is intentionally NOT in this list. Visible titles are
# always rendered through `Text(...)` (e.g. `AppBar(title: Text(...))`), while
# a bare `title: '...'` in this codebase is `ProblemError.title` diagnostic
# metadata that is never rendered — the UI branches on the stable `code` and
# shows catalog copy. Matching it here would only add false positives.
WIDGET_PARAMS='Text|label|tooltip|hintText|semanticsLabel|labelText|subtitle|helperText|errorText|message'

# Regex for a string literal that starts with a capital letter or a German
# umlaut — a user-facing sentence/label — assigned to a visible parameter.
CANDIDATE_RE="(${WIDGET_PARAMS})[[:space:]]*[:(].*['\"][A-ZÄÖÜ][^'\"]{2,}['\"]"

# Technical / allowlisted shapes that are never user-facing copy.
ALLOW_RE='(https?://|api\.[A-Za-z]|^SELECT|^INSERT|^UPDATE|^DELETE|^WITH |^FROM |^WHERE )'

violations=0

while IFS= read -r hit; do
  file="${hit%%:*}"
  rest="${hit#*:}"
  line="${rest%%:*}"
  code="${rest#*:}"
  code="$(printf '%s' "$code" | sed -E 's/^[[:space:]]+//')"

  # Skip the allowlisted technical shapes.
  if printf '%s' "$code" | grep -Eq "$ALLOW_RE"; then
    continue
  fi

  # Skip widget/test key identifiers (technical, never copy).
  if printf '%s' "$code" | grep -Eq "^Key\('[^']*'\)$"; then
    continue
  fi

  printf '%s:%s: user-facing inline copy must come from the ARB catalog: %s\n' \
    "$file" "$line" "$code" >&2
  violations=$((violations + 1))
done < <(
  grep -RInE "$CANDIDATE_RE" \
    --include='*.dart' \
    --exclude='*.g.dart' \
    --exclude='*.freezed.dart' \
    lib/features \
  | grep -vE '^\s*//' \
  | grep -vE ':[[:space:]]*(//|///)'
)

if [[ "$violations" -gt 0 ]]; then
  printf '\n%d user-facing inline copy literal(s) found under lib/features/**.\n' \
    "$violations" >&2
  printf 'Move them into lib/l10n/app_de.arb + app_en.arb and use l10nOf(context).\n' >&2
  printf 'Technical strings (keys, codes, URLs, diagnostics) are allowlisted by category.\n' >&2
  exit 1
fi

printf 'inline-copy gate: no user-facing literals under lib/features/**\n'
