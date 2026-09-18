#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0
# Copyright (C) 2024-2026 Breakdown RS Contributors
# Co-authored-by: deepseek-v4-flash (neuralwatt)
#
# Applies the tracked flutter_gherkin 2.0.0 VM-service regex patch to the
# pub-cache copy of the package, idempotently and from a clean checkout
# (issue #440).
#
# Why this exists: flutter_gherkin 2.0.0's `_observatoryDebuggerUriRegex` only
# matches the legacy "An Observatory debugger and profiler ... is available
# at:" launch output, while Flutter >= 3.x prints "A Dart VM Service on ... is
# available at: ...". Without the patch the on-device runner
# (tool/run_gherkin.sh) deterministically times out with
# "Timeout while waiting for observatory debugger uri". There is no upstream
# fix (flutter_gherkin 2.0.0, last published 2021), so the patch is tracked
# in-tree and applied to the pub-cache copy. tool/run_gherkin.sh invokes this
# before launching; tool/check_gherkin.sh uses `--check`.
#
# The patch is UPGRADE ME with the dependency: if flutter_gherkin resolves at
# a different version or the pub-cache layout changes, update PUB_CACHE path +
# PATCH_FILE matching (see the affected-packages note in tool/check_gherkin.sh).
#
# Idempotence: if the target already carries the patch's `dart vm service`
# alternative, this script is a no-op (exit 0). Presence of that literal line
# is the single source of truth for "patched".
#
# Usage:
#   bash tool/patch_gherkin.sh            # apply (idempotent)
#   bash tool/patch_gherkin.sh --check    # verify only; exit 1 if not applied
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PATCH_FILE="$ROOT/tool/patches/flutter_gherkin-2.0.0-vm-service.patch"

# flutter_gherkin 2.0.0's pubspec pins this lib path; the cache root honors
# PUB_CACHE (default ~/.pub-cache).
PUB_CACHE="${PUB_CACHE:-$HOME/.pub-cache}"
PKG_DIR="$PUB_CACHE/hosted/pub.dev/flutter_gherkin-2.0.0"
TARGET="$PKG_DIR/lib/src/flutter/flutter_run_process_handler.dart"
PATCHED_MARKER='dart vm service'

check_only=false
[ "${1:-}" = "--check" ] && check_only=true

is_patched() { grep -qF -- "$PATCHED_MARKER" "$TARGET"; }

if [ ! -f "$TARGET" ]; then
  msg="flutter_gherkin 2.0.0 not found at $TARGET — run 'flutter pub get' first (tool/run_gherkin.sh applies this patch after pub get)."
  if [ "$check_only" = true ]; then
    echo "::error ::$msg" >&2
  else
    echo "error: $msg" >&2
  fi
  exit 1
fi

if is_patched; then
  if [ "$check_only" = true ]; then
    echo "ok: flutter_gherkin VM-service patch applied ($TARGET)"
  else
    echo "flutter_gherkin VM-service patch already applied; nothing to do."
  fi
  exit 0
fi

if [ "$check_only" = true ]; then
  echo "::error ::flutter_gherkin VM-service patch NOT applied ($TARGET). Run 'bash tool/run_gherkin.sh' (which applies it before launching) or 'bash tool/patch_gherkin.sh'." >&2
  exit 1
fi

echo "Applying flutter_gherkin VM-service regex patch to $TARGET"
echo "  source: $PATCH_FILE"

# Pub archives ship CRLF line endings; git apply/GNU patch reject CRLF
# targets. Dart source is line-ending-agnostic, so LF-normalize the target in
# place before applying. The result is a valid, patched Dart file regardless of
# the original shape.
# Portable `sed -i`: BSD/macOS sed requires an explicit backup suffix argument.
sed -i.bak 's/\r$//' "$TARGET" && rm -f "$TARGET.bak"

(
  cd "$PKG_DIR" || exit 1
  # Prefer `git apply` (always present with a git checkout): it applies a
  # `a/…`/`b/…` patch with -p1 and its workspace handling is line-ending-
  # robust after the LF normalization above. Fall back to GNU/BSD `patch`.
  if ! git apply -p1 "$PATCH_FILE" 2>/dev/null; then
    patch -p1 --forward < "$PATCH_FILE"
  fi
)

if ! grep -qF -- "$PATCHED_MARKER" "$TARGET"; then
  echo "::error ::flutter_gherkin VM-service patch failed to apply cleanly to $TARGET" >&2
  exit 1
fi

echo "ok: flutter_gherkin VM-service regex patch applied."
