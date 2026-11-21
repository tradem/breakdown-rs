#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0
# Copyright (C) 2024-2026 Breakdown RS Contributors
# Co-authored-by: deepseek-v4.1-flash (opencode-go)

#
# Guard test for `scripts/release/check-flutter-aot-regression.sh` — the
# exit-code/state contract that `.github/workflows/flutter-aot-canary.yml`
# branches on (and that decides whether the `flutter-version` pin in
# `flutter-ci.yml` / `flutter-release.yml` may be lifted).
#
# The four promises:
#   1. **SDK older than 3.14.0 is `prereq`, never `fixed`.** An SDK that
#      predates dart-lang/sdk#64917 compiles the probe fine — reporting that as
#      "fixed" would lift the pin onto a still-broken toolchain.
#   2. **`linearscan.cc` in the failure → `broken` (exit 3).** The known
#      crash, and only the known crash, keeps the pin.
#   3. **Any other compile failure → `unknown` (exit 1).** Not a fix, not the
#      known regression: a human must look, and the canary must fail loudly
#      instead of silently reporting nothing.
#   4. **A clean compile → `fixed` (exit 0)**, and `state` / `dart_version` are
#      published through `$GITHUB_OUTPUT` whenever that is set.
#
# Daemon-free and toolchain-free: bash + coreutils, a `mktemp -d` fixture and a
# fake `dart` on PATH. No Flutter, no network, no AOT compile of the real probe
# (that is what the canary workflow is for).
#
# Usage: bash scripts/release/tests/check-flutter-aot-regression-test.sh

set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RELEASE_DIR="$(cd "${TEST_DIR}/.." && pwd)"
SCRIPT="${RELEASE_DIR}/check-flutter-aot-regression.sh"
PROBE="$(cd "${RELEASE_DIR}/../.." && pwd)/tool/aot-regressions/deferred_final_switch_closure.dart"

[ -f "$SCRIPT" ] || { printf 'missing script: %s\n' "$SCRIPT" >&2; exit 1; }
[ -f "$PROBE" ] || { printf 'missing AOT regression probe: %s\n' "$PROBE" >&2; exit 1; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/check-flutter-aot-regression-test.XXXXXX")"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

failures=0
check() { # check <description> <expected> <actual>
  if [ "$2" = "$3" ]; then
    printf '  ok    %s\n' "$1"
  else
    printf '  FAIL  %s (expected %s, got %s)\n' "$1" "$2" "$3" >&2
    failures=$((failures + 1))
  fi
}

# Fake `dart` launcher. FAKE_DART_VERSION / FAKE_DART_COMPILE decide the
# behaviour; the compile branch prints the failure and exits non-zero the way
# the real compiler does.
FAKE_BIN="$WORK/bin"
mkdir -p "$FAKE_BIN"
cat >"$FAKE_BIN/dart" <<'FAKE'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
  --version)
    printf 'Dart SDK version: %s (stable) (Wed Nov 4 16:28:39 2026 -0800) on "linux_x64"\n' \
      "${FAKE_DART_VERSION:?}"
    ;;
  compile)
    case "${FAKE_DART_COMPILE:?}" in
      ok)
        printf 'Generated: %s\n' "$4"
        ;;
      linearscan)
        printf '../../runtime/vm/compiler/backend/linearscan.cc: 3013: error: unreachable code\n' >&2
        printf 'Error: AOT compilation failed\n' >&2
        exit 254
        ;;
      other)
        printf 'repro.dart:7:3: Error: Expected a declaration, but got end of file.\n' >&2
        exit 254
        ;;
      *)
        printf 'unexpected FAKE_DART_COMPILE=%s\n' "$FAKE_DART_COMPILE" >&2
        exit 99
        ;;
    esac
    ;;
  *)
    printf 'unexpected fake dart invocation: %s\n' "$*" >&2
    exit 99
    ;;
esac
FAKE
chmod +x "$FAKE_BIN/dart"

run_case() { # run_case <version> <compile-mode> -> sets rc / state / out_version
  output="$WORK/github_output.txt"
  : >"$output"
  rc=0
  FAKE_DART_VERSION="$1" FAKE_DART_COMPILE="$2" \
    DART_BIN="$FAKE_BIN/dart" PROBE="$PROBE" GITHUB_OUTPUT="$output" \
    bash "$SCRIPT" >"$WORK/stdout.txt" 2>"$WORK/stderr.txt" || rc=$?
  state="$(sed -n 's/^state=//p' "$output" | head -n1)"
  out_version="$(sed -n 's/^dart_version=//p' "$output" | head -n1)"
}

printf 'check-flutter-aot-regression.sh guard test\n'

# 1. An SDK that predates the regression must never be read as "fixed".
run_case "3.13.2" "ok"
check "3.13.2 (predates the bug) exits 1" 1 "$rc"
check "3.13.2 reports prereq" "prereq" "$state"
check "3.13.2 publishes the SDK version" "3.13.2" "$out_version"
check "3.13.2 explains why it cannot judge" "1" \
  "$(grep -c 'predates the dart-lang/sdk#64917 regression' "$WORK/stdout.txt")"

# 2. The known crash keeps the pin: exit 3, state=broken, and the compiler log
#    is surfaced (not swallowed).
run_case "3.14.0" "linearscan"
check "3.14.0 + linearscan exit 3" 3 "$rc"
check "3.14.0 + linearscan reports broken" "broken" "$state"
check "3.14.0 + linearscan surfaces the crash" "1" \
  "$(grep -c 'linearscan.cc: 3013' "$WORK/stderr.txt")"
check "3.14.0 + linearscan names the upstream issue" "1" \
  "$(grep -c 'dart-lang/sdk/issues/64917' "$WORK/stdout.txt")"

# 3. A different compile failure is neither a fix nor the known bug.
run_case "3.14.0" "other"
check "3.14.0 + unrelated failure exits 1" 1 "$rc"
check "3.14.0 + unrelated failure reports unknown" "unknown" "$state"
check "3.14.0 + unrelated failure is an error annotation" "1" \
  "$(grep -c '::error::' "$WORK/stdout.txt")"

# 4. A clean compile means the pin can be lifted.
run_case "3.14.7" "ok"
check "3.14.7 + clean compile exits 0" 0 "$rc"
check "3.14.7 + clean compile reports fixed" "fixed" "$state"
check "3.14.7 + clean compile names both pin sites" "1" \
  "$(grep -c 'flutter-ci\.yml AND flutter-release\.yml' "$WORK/stdout.txt")"

# 5. A bigger version must not be classified by string order (3.9.0 < 3.14.0
#    numerically but sorts *after* it lexicographically).
run_case "3.9.0" "linearscan"
check "3.9.0 is older, not newer (prereq)" "prereq" "$state"

# 6. Without $GITHUB_OUTPUT (local hand-run) the script still works.
rc=0
FAKE_DART_VERSION="3.14.0" FAKE_DART_COMPILE="linearscan" \
  DART_BIN="$FAKE_BIN/dart" PROBE="$PROBE" \
  env -u GITHUB_OUTPUT bash "$SCRIPT" >/dev/null 2>&1 || rc=$?
check "no GITHUB_OUTPUT: still exits 3 on the known crash" 3 "$rc"

# 7. A missing probe fails loud instead of reporting a bogus state.
rc=0
FAKE_DART_VERSION="3.14.0" FAKE_DART_COMPILE="ok" \
  DART_BIN="$FAKE_BIN/dart" PROBE="$WORK/does-not-exist.dart" \
  GITHUB_OUTPUT="$WORK/output-missing-probe.txt" \
  bash "$SCRIPT" >"$WORK/stdout.txt" 2>&1 || rc=$?
check "missing probe exits 1" 1 "$rc"
check "missing probe says so" "1" "$(grep -c 'probe missing' "$WORK/stdout.txt")"

if [ "$failures" -ne 0 ]; then
  printf '\n%d check(s) failed.\n' "$failures" >&2
  exit 1
fi
printf '\nAll checks passed.\n'
