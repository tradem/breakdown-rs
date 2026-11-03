#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0
# Copyright (C) 2024-2026 Breakdown RS Contributors
# Co-authored-by: glm-5.3 (neuralwatt)
#
# Wrapper-level regression test for issue #810.
#
# The `business` reset drops the SierraDB volume *and then* replays the keep-list.
# On 2026-11-03 a run failed between those two steps and left an empty event
# store; the next run exported that empty store (`10 streams / 0 events`) and
# exited 0 after "replaying" nothing.
#
# This test drives the real `scripts/reset-dev-data.sh` with three seams and no
# docker, no database and no event store:
#
#   * `RESET_DEV_DATA_BIN` — a fake `reset-dev-data` binary that fails at a
#     chosen phase (the testability seam added with this issue),
#   * a `docker`/`curl` shim on `PATH` (context, compose, volume and pg_dump
#     calls answered locally),
#   * a throwaway TCP listener standing in for SierraDB's readiness probe.
#
# Asserted here:
#   1. a failure after the volume drop restores the keep-list (volume dropped
#      again, replay re-run) and still exits non-zero,
#   2. nothing on that path prints the success/"next steps" block,
#   3. the pre-drop keep-list summary names the event counts (`0 event(s)`
#     included — the visibility half of the issue),
#   4. a failure *before* the volume drop never touches the volume or replays,
#   5. a clean run still succeeds and prints the next steps exactly once.
#
# Usage: bash scripts/tests/reset-dev-data-wrapper-test.sh

set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKEND_DIR="$(cd "${TEST_DIR}/../.." && pwd)"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/reset-wrapper-test.XXXXXX")"
LISTENER_PID=""
cleanup() {
  if [[ -n "${LISTENER_PID}" ]]; then
    kill "${LISTENER_PID}" 2>/dev/null || true
  fi
  rm -rf "${WORK}"
}
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
  if "$@"; then
    pass "${description}"
  else
    fail "${description}"
  fi
}

# ── fake backend tree ────────────────────────────────────────────────────────
# The wrapper derives BACKEND_DIR from its own path and sources the git-ignored
# `.env*` files from there, so a copy keeps the developer's real stack (and its
# environment) out of the test.
FAKE_BACKEND="${WORK}/backend"
mkdir -p "${FAKE_BACKEND}/scripts" "${FAKE_BACKEND}/backups" "${WORK}/bin"
cp "${BACKEND_DIR}/scripts/reset-dev-data.sh" "${FAKE_BACKEND}/scripts/"
cp "${BACKEND_DIR}/docker-compose.dev.yml" "${FAKE_BACKEND}/"

# ── docker + curl shims ──────────────────────────────────────────────────────
cat > "${WORK}/bin/docker" <<'SHIM'
#!/usr/bin/env bash
# Fake docker: answers everything `reset-dev-data.sh` asks, logs every call.
set -u
printf '%s\n' "$*" >> "${DOCKER_LOG}"
case "${1:-}" in
  context)
    case "${2:-}" in
      show) printf 'default\n' ;;
      inspect) printf 'unix:///var/run/docker.sock\n' ;;
      *) exit 1 ;;
    esac
    ;;
  compose)
    shift
    while [[ $# -gt 0 ]]; do
      case "$1" in
        -f) shift 2 ;;
        *) break ;;
      esac
    done
    case "${1:-}" in
      ps) printf 'fake-container\n' ;;
      *) : ;;
    esac
    exit 0
    ;;
  inspect) printf 'fake-volume\n' ;;
  volume) exit 0 ;;
  ps) : ;;
  run) exit 0 ;;
  *) exit 0 ;;
esac
SHIM
cat > "${WORK}/bin/curl" <<'SHIM'
#!/usr/bin/env bash
# Fake curl: the API is stopped, so /v1/health never answers.
exit 1
SHIM
chmod +x "${WORK}/bin/docker" "${WORK}/bin/curl"

# ── fake reset-dev-data binary (RESET_DEV_DATA_BIN) ──────────────────────────
cat > "${WORK}/bin/reset-dev-data" <<'FAKE'
#!/usr/bin/env bash
# Fake `reset-dev-data`: records its arguments, writes the keep-list on the
# export phase and fails at the phase named in FAKE_FAIL_PHASE.
set -u
printf '%s\n' "$*" >> "${BIN_LOG}"

phase=""
backup_dir=""
previous=""
for arg in "$@"; do
  case "${previous}" in
    --phase) phase="${arg}" ;;
    --backup-dir) backup_dir="${arg}" ;;
  esac
  previous="${arg}"
done

case "${phase}" in
  export)
    mkdir -p "${backup_dir}"
    cat > "${backup_dir}/keep-list.json" <<'JSON'
{
  "format_version": 1,
  "created_at": "2026-11-03T05:00:54.548801015Z",
  "database_target": "localhost/breakdown",
  "streams": [
    {
      "stream_id": "ai_config-01a02b40-1000-7000-8000-000000000001",
      "category": "ai_config",
      "events": []
    },
    {
      "stream_id": "settings-01a02b40-1000-7000-8000-000000000002",
      "category": "settings",
      "events": []
    }
  ]
}
JSON
    ;;
  wipe | replay | verify) : ;;
  *)
    printf 'fake reset-dev-data: unexpected --phase %s\n' "${phase}" >&2
    exit 1
    ;;
 esac

# `FAKE_SLEEP_PHASE` keeps a phase "in flight" so the test can interrupt the
# wrapper mid-window (SIGTERM/SIGHUP scenario, issue #810 review).
if [[ "${FAKE_SLEEP_PHASE:-}" == "${phase}" ]]; then
  sleep "${FAKE_SLEEP_SECONDS:-3}"
fi

if [[ "${FAKE_FAIL_PHASE:-}" == "${phase}" ]]; then
  printf 'fake reset-dev-data: injected failure at phase %s\n' "${phase}" >&2
  exit 1
fi

printf '== reset-dev-data (fake): %s ==\n' "$*"
FAKE
chmod +x "${WORK}/bin/reset-dev-data"

# ── SierraDB readiness listener ──────────────────────────────────────────────
# `require_stack_running` opens a TCP connection to SIERRADB_URL's host:port; a
# throwaway listener keeps that check (and its 60 s poll) out of the test.
PORT_FILE="${WORK}/sierradb.port"
python3 - "${PORT_FILE}" <<'PY' &
import socket
import sys

server = socket.socket()
server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
server.bind(("127.0.0.1", 0))
server.listen(64)
with open(sys.argv[1], "w", encoding="utf-8") as handle:
    handle.write(str(server.getsockname()[1]))
while True:
    try:
        connection, _ = server.accept()
        connection.close()
    except OSError:
        break
PY
LISTENER_PID=$!
for _ in $(seq 1 100); do
  [[ -s "${PORT_FILE}" ]] && break
  sleep 0.05
done
if [[ ! -s "${PORT_FILE}" ]]; then
  printf 'FAIL - the fake SierraDB listener did not start\n'
  exit 1
fi
SIERRADB_PORT="$(cat "${PORT_FILE}")"

# ── run helper ───────────────────────────────────────────────────────────────
#
# `run_wrapper` feeds `stdin_text` (the confirmation phrase, empty when `--yes`
# is passed) and forwards the remaining arguments to the wrapper.
run_wrapper() {
  local name="$1"
  local fail_phase="$2"
  local stdin_text="$3"
  shift 3
  DOCKER_LOG="${WORK}/${name}.docker.log"
  BIN_LOG="${WORK}/${name}.bin.log"
  : > "${DOCKER_LOG}"
  : > "${BIN_LOG}"
  set +e
  OUTPUT="$(cd "${FAKE_BACKEND}" && \
    printf '%s' "${stdin_text}" | \
    PATH="${WORK}/bin:${PATH}" \
    RESET_DEV_DATA_BIN="${WORK}/bin/reset-dev-data" \
    DOCKER_LOG="${DOCKER_LOG}" \
    BIN_LOG="${BIN_LOG}" \
    FAKE_FAIL_PHASE="${fail_phase}" \
    DATABASE_URL="postgres://postgres:postgres@127.0.0.1:5432/breakdown" \
    SIERRADB_URL="redis://127.0.0.1:${SIERRADB_PORT}/0?protocol=resp3" \
    bash "${FAKE_BACKEND}/scripts/reset-dev-data.sh" business "$@" \
      --no-backup --backup-dir "${WORK}/${name}-backup" 2>&1)"
  STATUS=$?
  set -e
}

run_business() {
  run_wrapper "$1" "$2" "" --yes
}

# Sends a signal to the wrapper while the fake `wipe` phase is in flight.
run_business_signal() {
  local name="$1"
  local signal="$2"
  DOCKER_LOG="${WORK}/${name}.docker.log"
  BIN_LOG="${WORK}/${name}.bin.log"
  : > "${DOCKER_LOG}"
  : > "${BIN_LOG}"
  local out_file="${WORK}/${name}.out"
  set +e
  ( cd "${FAKE_BACKEND}" && \
    PATH="${WORK}/bin:${PATH}" \
    RESET_DEV_DATA_BIN="${WORK}/bin/reset-dev-data" \
    DOCKER_LOG="${DOCKER_LOG}" \
    BIN_LOG="${BIN_LOG}" \
    FAKE_SLEEP_PHASE=wipe \
    FAKE_SLEEP_SECONDS=5 \
    DATABASE_URL="postgres://postgres:postgres@127.0.0.1:5432/breakdown" \
    SIERRADB_URL="redis://127.0.0.1:${SIERRADB_PORT}/0?protocol=resp3" \
    exec bash "${FAKE_BACKEND}/scripts/reset-dev-data.sh" business --yes --no-backup \
      --backup-dir "${WORK}/${name}-backup" > "${out_file}" 2>&1 ) &
  local pid=$!
  for _ in $(seq 1 200); do
    [[ -s "${BIN_LOG}" ]] && grep -q -- "--phase wipe" "${BIN_LOG}" && break
    sleep 0.05
  done
  sleep 0.3
  kill -s "${signal}" "${pid}" 2>/dev/null || true
  wait "${pid}"
  STATUS=$?
  OUTPUT="$(cat "${out_file}" 2>/dev/null || true)"
  set -e
}

count_in() { grep -c -- "$2" "$1" 2>/dev/null || true; }

# ── scenario 1: the wipe fails after the volume drop ─────────────────────────
run_business wipe-failure wipe
printf '%s\n' "${OUTPUT}" > "${WORK}/wipe-failure.out"

check "a failed wipe exits non-zero" test "${STATUS}" -ne 0
check "the keep-list summary is printed before the drop" \
  grep -q "keep ai_config" "${WORK}/wipe-failure.out"
check "the empty keep-list is called out as 'NO events'" \
  grep -q "this export carries NO events" "${WORK}/wipe-failure.out"
check "the restore is announced" \
  grep -q "the destructive window failed" "${WORK}/wipe-failure.out"
check "the keep-list is replayed by the trap after the failed wipe" \
  eval 'tail -n 1 "${BIN_LOG}" | grep -q -- "--phase replay"'
check "the volume is dropped twice (initial reset + restore)" \
  test "$(count_in "${DOCKER_LOG}" "volume rm")" -eq 2
check "the restore reports success" \
  grep -q "the keep-list was replayed into a fresh event store" "${WORK}/wipe-failure.out"
check "no success block is printed" \
  eval '! grep -q "next steps" "${WORK}/wipe-failure.out"'

# ── scenario 2: the export fails before anything destructive ─────────────────
run_business export-failure export
printf '%s\n' "${OUTPUT}" > "${WORK}/export-failure.out"

check "a failed export exits non-zero" test "${STATUS}" -ne 0
check "no volume is dropped when the export fails" \
  test "$(count_in "${DOCKER_LOG}" "volume rm")" -eq 0
check "nothing is replayed when the export fails" \
  test "$(count_in "${BIN_LOG}" "--phase replay")" -eq 0
check "the restore stays unarmed before the volume drop" \
  eval '! grep -q "restoring the keep-list" "${WORK}/export-failure.out"'

# ── scenario 3: the clean run ────────────────────────────────────────────────
run_business success ""
printf '%s\n' "${OUTPUT}" > "${WORK}/success.out"

check "a clean run exits zero" test "${STATUS}" -eq 0
check "the clean run drops the volume exactly once" \
  test "$(count_in "${DOCKER_LOG}" "volume rm")" -eq 1
check "the clean run replays exactly once" \
  test "$(count_in "${BIN_LOG}" "--phase replay")" -eq 1
check "the clean run prints the next steps" \
  grep -q "next steps" "${WORK}/success.out"
check "the clean run does not run the restore" \
  eval '! grep -q "destructive window failed" "${WORK}/success.out"'

# ── scenario 4: a signal during the destructive window ──────────────────────
# bash runs the EXIT trap with `$? = 0` after SIGTERM/SIGHUP, so without the
# explicit signal traps the restore is skipped and the store stays empty
# (issue #810 review).
for signal in TERM HUP; do
  name="signal-${signal}"
  run_business_signal "${name}" "${signal}"
  printf '%s\n' "${OUTPUT}" > "${WORK}/${name}.out"
  check "SIG${signal} in the destructive window exits non-zero" test "${STATUS}" -ne 0
  check "SIG${signal} announces the restore" \
    grep -q "the destructive window failed" "${WORK}/${name}.out"
  check "SIG${signal} replays the keep-list from the trap" \
    eval 'tail -n 1 "${BIN_LOG}" | grep -q -- "--phase replay"'
  check "SIG${signal} recreates the volume (initial drop + restore)" \
    test "$(count_in "${DOCKER_LOG}" "volume rm")" -eq 2
  check "SIG${signal} reports a successful restore" \
    grep -q "the keep-list was replayed into a fresh event store" "${WORK}/${name}.out"
done

# ── scenario 5: the `business-empty` confirmation ───────────────────────────
# Interactive runs (no `--yes`) read the phrase from stdin; `--allow-empty-keep-list`
# must demand the stricter one. Nothing tested this path before (issue #810 review).
run_wrapper empty-confirm-accepted "" "business-empty
" --allow-empty-keep-list
printf '%s\n' "${OUTPUT}" > "${WORK}/empty-confirm-accepted.out"
check "the business-empty phrase proceeds" test "${STATUS}" -eq 0
check "the accepted run forwards --allow-empty-keep-list to the export" \
  grep -q -- "--phase export.*--allow-empty-keep-list" "${BIN_LOG}"

run_wrapper empty-confirm-rejected "" "business
" --allow-empty-keep-list
printf '%s\n' "${OUTPUT}" > "${WORK}/empty-confirm-rejected.out"
check "the plain business phrase aborts the --allow-empty-keep-list run" \
  test "${STATUS}" -ne 0
check "the aborted run says so" \
  grep -q "aborted" "${WORK}/empty-confirm-rejected.out"
check "the aborted run never calls the binary" test "$(count_in "${BIN_LOG}" "--phase")" -eq 0
check "the aborted run drops no volume" test "$(count_in "${DOCKER_LOG}" "volume rm")" -eq 0

if [[ "${FAILURES}" -ne 0 ]]; then
  # Keep the artifacts of a failing run for inspection (the EXIT trap would
  # delete them) and print the captured wrapper output: a CI log without it
  # leaves the reader guessing (the 5.2-vs-5.3 `return` regression was only
  # visible here).
  trap - EXIT
  if [[ -n "${LISTENER_PID}" ]]; then
    kill "${LISTENER_PID}" 2>/dev/null || true
  fi
  printf '\n%s check(s) failed\n' "${FAILURES}"
  for scenario in wipe-failure export-failure success; do
    if [[ -f "${WORK}/${scenario}.out" ]]; then
      printf '\n--- %s (wrapper output) ---\n' "${scenario}"
      cat "${WORK}/${scenario}.out"
    fi
  done
  printf '\nartifacts kept in %s\n' "${WORK}"
  exit 1
fi
printf '\nall wrapper checks passed\n'
