#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0
# Copyright (C) 2024-2026 Breakdown RS Contributors
# Co-authored-by: deepseek-v4.1-flash (opencode-go)
#
# Regression test for `scripts/reclaim-disk.sh` (AGENTS.md §8 / issue #631).
#
# The script deletes build artifacts, so its two invariants are tested here:
#
#   1. **Nothing is deleted without `--apply`.** `target/` held 857 GB on this
#      workspace (534 GB incremental caches); a hygiene helper that silently
#      reclaims would be worse than the problem.
#   2. **A missing `cargo-sweep` is reported, not ignored.** Without the tool the
#      script must say how to install it, and `--apply` must fail so a wrapper
#      script cannot mistake "nothing installed" for "nothing to do".
#
# Everything runs against a throwaway Cargo project in `mktemp -d`: no docker, no
# database, no network.
#
# Usage: bash scripts/tests/reclaim-disk-test.sh

set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKEND_DIR="$(cd "${TEST_DIR}/../.." && pwd)"
SCRIPT="${BACKEND_DIR}/scripts/reclaim-disk.sh"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/reclaim-disk-test.XXXXXX")"
cleanup() { rm -rf "${WORK}"; }
trap cleanup EXIT

FAILURES=0
pass() { printf 'ok   - %s\n' "$1"; }
fail() {
  printf 'FAIL - %s\n' "$1"
  FAILURES=$((FAILURES + 1))
}
check() {
  local description="$1"
  shift
  if "$@"; then pass "${description}"; else fail "${description}"; fi
}

# ── a throwaway project with a fake, fat incremental cache ───────────────────
FAKE_BACKEND="${WORK}/backend"
mkdir -p "${FAKE_BACKEND}/scripts" \
  "${FAKE_BACKEND}/target/debug/incremental/fake-cache" \
  "${FAKE_BACKEND}/target/debug/deps"
cp "${SCRIPT}" "${FAKE_BACKEND}/scripts/reclaim-disk.sh"
printf 'x' > "${FAKE_BACKEND}/target/debug/incremental/fake-cache/blob"
printf 'x' > "${FAKE_BACKEND}/target/debug/deps/fake-rlib"
touch -d '90 days ago' \
  "${FAKE_BACKEND}/target/debug/incremental/fake-cache/blob" \
  "${FAKE_BACKEND}/target/debug/deps/fake-rlib"

artifact_count() { find "${FAKE_BACKEND}/target" -type f | wc -l | tr -d ' '; }

# ── 1. --help documents the dry-run default ─────────────────────────────────
help_out="$(bash "${SCRIPT}" --help 2>&1)"
check "--help exits zero and names the dry-run default" \
  grep -q "report only" <<<"${help_out}"
check "--help names the cargo-sweep install command" \
  grep -q "cargo install cargo-sweep" <<<"${help_out}"

# ── 2. argument validation ──────────────────────────────────────────────────
set +e
bash "${SCRIPT}" --nonsense >/dev/null 2>&1
unknown_status=$?
bash "${SCRIPT}" --days not-a-number >/dev/null 2>&1
days_status=$?
set -e
check "an unknown argument exits non-zero" test "${unknown_status}" -ne 0
check "a non-numeric --days exits non-zero" test "${days_status}" -ne 0

# ── 3. the default run is a dry run: not a single file disappears ────────────
before="$(artifact_count)"
set +e
dry_out="$(cd "${FAKE_BACKEND}" && bash scripts/reclaim-disk.sh 2>&1)"
dry_status=$?
set -e
after="$(artifact_count)"

check "the default run exits zero" test "${dry_status}" -eq 0
check "the default run deletes nothing" test "${after}" -eq "${before}"
check "the default run announces that it is a dry run" \
  grep -q "dry run — nothing is deleted" <<<"${dry_out}"
check "the report names the incremental cache as the main grower" \
  grep -q "incremental" <<<"${dry_out}"

# ── 4. --apply reports the missing tool instead of pretending to work ───────
# `cargo-sweep` is deliberately absent from the CI images; when it *is*
# installed this assertion is skipped (the sweep itself is cargo's business).
if ! cargo sweep --version >/dev/null 2>&1; then
  set +e
  apply_out="$(cd "${FAKE_BACKEND}" && bash scripts/reclaim-disk.sh --apply 2>&1)"
  apply_status=$?
  set -e
  check "--apply without cargo-sweep exits non-zero" test "${apply_status}" -ne 0
  check "--apply without cargo-sweep prints the install command" \
    grep -q "cargo install cargo-sweep" <<<"${apply_out}"
  check "--apply without cargo-sweep deletes nothing" test "$(artifact_count)" -eq "${before}"
else
  pass "cargo-sweep is installed — the missing-tool path is not exercised"
fi

if [[ "${FAILURES}" -ne 0 ]]; then
  printf '\n%s check(s) failed\n' "${FAILURES}"
  exit 1
fi
printf '\nall reclaim-disk checks passed\n'
