#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0
# Copyright (C) 2024-2026 Breakdown RS Contributors
# Co-authored-by: deepseek-v4.1-flash (opencode-go)

#
# check-flutter-aot-regression.sh — does the active Dart SDK still AOT-compile
# the known-bad source shape?
#
# Answers ONE question, cheaply: does the active Dart SDK abort while
# AOT-compiling the regression probe in `tool/aot-regressions/`? That probe
# carries the exact source shape that Dart 3.14.0 (shipped in Flutter 3.50.x)
# miscompiled — a deferred `final` assigned in a pattern `switch` case and
# captured by a closure (dart-lang/sdk#64917):
#
#     runtime/vm/compiler/backend/linearscan.cc: 3013: error: unreachable code
#     Dart snapshot generator failed with exit code -6
#
# The JIT compiles it fine, so this is what killed the v0.4.0 release build
# (`:app:compileFlutterBuildProdRelease` → `android_aot_release_android-*`)
# while every JIT/debug gate stayed green, and it is why `flutter-version` is
# pinned instead of floating on `channel: stable`.
#
# `dart compile aot-snapshot` uses the SAME `gen_snapshot` as a release build,
# so the probe reproduces the failure in seconds — no Gradle, no Android SDK,
# no signing secrets, no keystore.
#
# This script is the smoke gate for that hazard class:
#   * `.github/workflows/flutter-ci.yml` runs it in `format-and-analyze`
#     against the PINNED SDK, so a bump onto a broken snapshotter fails the PR
#     instead of a release pipeline.
#   * run it by hand before touching the pin:
#       bash frontend-flutter/scripts/release/check-flutter-aot-regression.sh
#
# Exit / state contract (`tests/check-flutter-aot-regression-test.sh` guards it
# — do not change it silently):
#   0  state=fixed    the probe compiles → the snapshotter handles this shape
#   3  state=broken   the probe aborts in linearscan.cc → do not ship this SDK
#   1  state=prereq   SDK older than 3.14.0: it never had the bug, so the
#                     result says nothing about the pinned toolchain
#   1  state=unknown  a different compile failure — investigate, do not assume
#                     the regression is fixed or still present
#
# Environment:
#   DART_BIN       optional — dart launcher (default: `dart` on PATH)
#   PROBE          optional — probe source (default: the repo probe)
#   GITHUB_OUTPUT  optional — when set (i.e. in Actions) `state` and
#                  `dart_version` are published as step outputs
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# .../frontend-flutter/scripts/release -> frontend-flutter
FLUTTER_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
PROBE="${PROBE:-$FLUTTER_DIR/tool/aot-regressions/deferred_final_switch_closure.dart}"
DART_BIN="${DART_BIN:-dart}"

# The first Dart release carrying the regression. An older SDK cannot answer
# the question at all, so it must not be reported as `fixed`.
LOWEST_MEANINGFUL="3.14.0"

state="unknown"
dart_version="unknown"

publish_outputs() {
  [ -n "${GITHUB_OUTPUT:-}" ] || return 0
  {
    printf 'state=%s\n' "$state"
    printf 'dart_version=%s\n' "$dart_version"
  } >>"$GITHUB_OUTPUT"
}

finish() {
  publish_outputs
  exit "$1"
}

if [ ! -f "$PROBE" ]; then
  echo "::error::AOT regression probe missing: $PROBE"
  finish 1
fi

if ! version_line="$("$DART_BIN" --version 2>&1)"; then
  echo "::error::Cannot determine the Dart SDK version via '$DART_BIN --version': $version_line"
  finish 1
fi
# e.g. `Dart SDK version: 3.14.0 (stable) (Wed Nov 4 …) on "linux_x64"`
dart_version="$(printf '%s\n' "$version_line" | sed -n 's/.*version: \([^ ]*\).*/\1/p' | head -n1)"
if [ -z "$dart_version" ]; then
  echo "::error::Unparseable Dart version line: $version_line"
  finish 1
fi

# Numeric (sort -V) comparison: is the active SDK old enough to predate the bug?
newest_of_pair="$(printf '%s\n%s\n' "$LOWEST_MEANINGFUL" "$dart_version" | sort -V | tail -n1)"
if [ "$newest_of_pair" != "$dart_version" ]; then
  state="prereq"
  echo "::notice::Dart $dart_version predates the dart-lang/sdk#64917 regression (first affected: $LOWEST_MEANINGFUL) — probe not meaningful, this SDK cannot judge the shape. Use a Flutter/Dart >= $LOWEST_MEANINGFUL."
  finish 1
fi

work="$(mktemp -d "${TMPDIR:-/tmp}/flutter-aot-regression.XXXXXX")"
trap 'rm -rf "$work"' EXIT

echo "Compiling the dart-lang/sdk#64917 probe with Dart $dart_version …"
rc=0
compile_log="$("$DART_BIN" compile aot-snapshot "$PROBE" -o "$work/probe.aot" 2>&1)" || rc=$?

if [ "$rc" -eq 0 ]; then
  state="fixed"
  echo "::notice::AOT regression probe compiles on Dart $dart_version — the release AOT snapshotter handles the dart-lang/sdk#64917 shape, so this SDK is safe to pin in .github/workflows/flutter-ci.yml AND flutter-release.yml."
  finish 0
fi

printf '%s\n' "$compile_log" >&2
if printf '%s\n' "$compile_log" | grep -q 'linearscan\.cc'; then
  state="broken"
  echo "::notice::AOT regression still present on Dart $dart_version (linearscan.cc UNREACHABLE, exit $rc) — do not pin or ship this SDK. Tracked upstream: https://github.com/dart-lang/sdk/issues/64917"
  finish 3
fi

echo "::error::The probe failed to AOT-compile on Dart $dart_version for a DIFFERENT reason (exit $rc) — that is neither the known regression nor a fix. Read the log above before touching the pin."
finish 1
