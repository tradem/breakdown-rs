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
# A real (tiny) Cargo project, because `cargo sweep` propagates its exit status
# now: on a non-project directory the dry run legitimately fails.
FAKE_BACKEND="${WORK}/backend"
mkdir -p "${FAKE_BACKEND}/scripts" "${FAKE_BACKEND}/src" \
  "${FAKE_BACKEND}/target/debug/incremental/fake-cache" \
  "${FAKE_BACKEND}/target/debug/deps"
cat > "${FAKE_BACKEND}/Cargo.toml" <<'TOML'
[package]
name = "reclaim-disk-fixture"
version = "0.1.0"
edition = "2021"

[lib]
path = "src/lib.rs"
TOML
printf '// fixture\n' > "${FAKE_BACKEND}/src/lib.rs"
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

# ── 4. --apply reports a missing/failing tool instead of pretending to work ──
# The CI image has no `cargo-sweep`, so both cases are simulated with a `cargo`
# shim on PATH — deterministic on every runner, with or without the real tool.
NOSWEEP_BIN="${WORK}/bin-nosweep"
FAILSWEEP_BIN="${WORK}/bin-failsweep"
mkdir -p "${NOSWEEP_BIN}" "${FAILSWEEP_BIN}"
REAL_CARGO="$(command -v cargo 2>/dev/null || true)"
cat > "${NOSWEEP_BIN}/cargo" <<SHIM
#!/usr/bin/env bash
if [[ "\${1:-}" == "sweep" ]]; then echo 'error: no such command: sweep' >&2; exit 1; fi
exec ${REAL_CARGO:-/bin/false} "\$@"
SHIM
cat > "${FAILSWEEP_BIN}/cargo" <<SHIM
#!/usr/bin/env bash
if [[ "\${1:-}" == "sweep" ]]; then
  case " \$* " in
    *" --version "*) echo 'cargo-sweep-sweep 0.8.0'; exit 0 ;;
    *) echo 'cargo sweep: simulated failure' >&2; exit 3 ;;
  esac
fi
exec ${REAL_CARGO:-/bin/false} "\$@"
SHIM
chmod +x "${NOSWEEP_BIN}/cargo" "${FAILSWEEP_BIN}/cargo"

set +e
apply_out="$(cd "${FAKE_BACKEND}" && PATH="${NOSWEEP_BIN}:${PATH}" bash scripts/reclaim-disk.sh --apply 2>&1)"
apply_status=$?
set -e
check "--apply without cargo-sweep exits non-zero" test "${apply_status}" -ne 0
check "--apply without cargo-sweep prints the install command" \
  grep -q "cargo install cargo-sweep" <<<"${apply_out}"
check "--apply without cargo-sweep says no build artifacts were deleted" \
  grep -q "no build artifacts were deleted" <<<"${apply_out}"
check "--apply without cargo-sweep deletes nothing" test "$(artifact_count)" -eq "${before}"

# A failed sweep must not be reported as success (review finding).
set +e
failing_out="$(cd "${FAKE_BACKEND}" && PATH="${FAILSWEEP_BIN}:${PATH}" bash scripts/reclaim-disk.sh --apply 2>&1)"
failing_status=$?
set -e
check "a failing cargo sweep makes --apply exit non-zero" test "${failing_status}" -ne 0
check "a failing cargo sweep is called out" grep -q "the sweep did not complete" <<<"${failing_out}"

# ── 5. docker reporting: failures do not abort, sizes are parsed by unit ─────
# `docker system df` failing must not stop the sweep (review finding), and the
# writable-layer warning has to understand fractional GB and TB sizes.
DOCKER_BIN="${WORK}/bin-docker"
mkdir -p "${DOCKER_BIN}"
cat > "${DOCKER_BIN}/docker" <<'SHIM'
#!/usr/bin/env bash
# Fake docker: an unhealthy `system df`, plus containers with every size unit.
set -u
case "${1:-}" in
  info) exit 0 ;;
  system) echo 'cannot connect to the daemon' >&2; exit 1 ;;
  ps)
    if [[ " $* " == *" --size "* ]]; then
      printf 'aaa\tpython:3.12-slim\tUp 2 hours\t601GB (virtual 601GB)\n'
      printf 'bbb\tpython:3.12-slim\tUp 1 hour\t20.5GB (virtual 20.5GB)\n'
      printf 'ccc\tpostgres:16\tUp 1 hour\t1.2TB\n'
      printf 'ddd\tpostgres:16\tUp 1 hour\t500MB\n'
      exit 0
    fi
    exit 0
    ;;
  *) exit 0 ;;
esac
SHIM
chmod +x "${DOCKER_BIN}/docker"

set +e
docker_out="$(cd "${FAKE_BACKEND}" && PATH="${DOCKER_BIN}:${NOSWEEP_BIN}:${PATH}" \
  bash scripts/reclaim-disk.sh 2>&1)"
docker_status=$?
set -e
check "a failing docker query does not abort the report" test "${docker_status}" -eq 0
check "the target report is still printed after the docker failure" \
  grep -q "target/ (" <<<"${docker_out}"
check "a whole-GB writable layer warns" \
  eval 'grep -q "WARNING: container aaa" <<<"${docker_out}"'
check "a fractional-GB writable layer warns" \
  eval 'grep -q "WARNING: container bbb" <<<"${docker_out}"'
check "a terabyte writable layer warns" \
  eval 'grep -q "WARNING: container ccc" <<<"${docker_out}"'
check "a megabyte writable layer does not warn" \
  eval '! grep -q "WARNING: container ddd" <<<"${docker_out}"'

# The missing-tool message must not claim "nothing was deleted" when
# `--apply --with-docker` already pruned containers (review finding).
set +e
pruned_out="$(cd "${FAKE_BACKEND}" && PATH="${DOCKER_BIN}:${NOSWEEP_BIN}:${PATH}" \
  bash scripts/reclaim-disk.sh --apply --with-docker 2>&1)"
set -e
check "a --with-docker run mentions the pruned containers in the missing-tool message" \
  grep -q "stopped containers were pruned above" <<<"${pruned_out}"

# ── 6. a relative CARGO_TARGET_DIR resolves against the caller ──────────────
# The sweep runs in a subshell that `cd`s into `backend/`, so an unresolved
# relative path would mean two different directories (review finding).
set +e
relative_out="$(cd "${WORK}" && CARGO_TARGET_DIR="backend/target" \
  PATH="${NOSWEEP_BIN}:${PATH}" bash "${FAKE_BACKEND}/scripts/reclaim-disk.sh" 2>&1)"
set -e
check "a relative CARGO_TARGET_DIR is resolved against the caller's directory" \
  grep -q "target/ (${WORK}/backend/target)" <<<"${relative_out}"

if [[ "${FAILURES}" -ne 0 ]]; then
  printf '\n%s check(s) failed\n' "${FAILURES}"
  exit 1
fi
printf '\nall reclaim-disk checks passed\n'
