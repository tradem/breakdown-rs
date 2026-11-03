#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0
# Copyright (C) 2024-2026 Breakdown RS Contributors
# Co-authored-by: deepseek-v4.1-flash (opencode-go)
#
# Dev-machine disk hygiene (AGENTS.md §8, issue #631).
#
# `cargo` never garbage-collects stale artifacts: every changed source/flags
# combination leaves the previous binary and an incremental cache behind. On
# this workspace `target/` reached **857 GB** (534 GB of it
# `target/debug/incremental/`) on a 950 GB disk — and a single forgotten
# container added another 601 GB. This script makes the reclaim a reviewable
# step instead of a `rm -rf` panic.
#
#   ./scripts/reclaim-disk.sh                 # report only (default)
#   ./scripts/reclaim-disk.sh --apply         # sweep artifacts older than 30 days
#   ./scripts/reclaim-disk.sh --apply -t 7    # ... older than a week
#   ./scripts/reclaim-disk.sh --apply --maxsize 200GB
#   ./scripts/reclaim-disk.sh --report --with-docker   # docker footprint + oversized containers
#   ./scripts/reclaim-disk.sh --apply --with-docker    # ... and prune stopped containers
#
# The default is a dry run: nothing is deleted without `--apply` (mirrors the
# `--dry-run`/`--no-backup` discipline of `reset-dev-data.sh`). `--with-docker`
# on its own only *reports* — pruning stopped containers needs `--apply` too.
#
# `cargo sweep` (cargo-sweep) is the tool that does the actual work; it is a
# **local dev tool**, not a workspace dependency:
#
#   cargo install cargo-sweep --locked --version 0.8.0
#
# Without it this script still reports the sizes and says what it would do.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKEND_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
TARGET_DIR="${CARGO_TARGET_DIR:-${BACKEND_DIR}/target}"
# A relative `CARGO_TARGET_DIR` must be resolved **once**, against the caller's
# directory: the sweep runs in a subshell that `cd`s into `backend/`, so a
# relative path would mean two different directories (review finding).
case "${TARGET_DIR}" in
  /*) ;;
  *) TARGET_DIR="${PWD}/${TARGET_DIR}" ;;
esac
# A writable layer above this is almost always a container that copied a build
# tree into itself (observed: 601 GB) — flag it instead of letting df surprise us.
CONTAINER_WARN_GB="${CONTAINER_WARN_GB:-20}"

apply=0
days=30
maxsize=""
with_docker=0

usage() {
  sed -n '6,30p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

die() {
  printf 'reclaim-disk: %s\n' "$1" >&2
  exit 1
}

log() {
  printf '==> %s\n' "$1"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply) apply=1; shift ;;
    --report|--dry-run) apply=0; shift ;;
    -t|--days) days="${2:?--days requires a number}"; shift 2 ;;
    --maxsize) maxsize="${2:?--maxsize requires a size (e.g. 200GB)}"; shift 2 ;;
    --with-docker) with_docker=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown argument $1 (try --help)" ;;
  esac
done

[[ "${days}" =~ ^[0-9]+$ ]] || die "--days must be a non-negative integer, got ${days}"

# Prints a human-readable size of a path, `0 B` when it does not exist.
size_of() {
  local path="$1"
  if [[ ! -e "${path}" ]]; then
    printf '0 B'
    return
  fi
  du -sh "${path}" 2>/dev/null | cut -f1
}

report_target() {
  printf '\ntarget/ (%s)\n' "${TARGET_DIR}"
  if [[ ! -d "${TARGET_DIR}" ]]; then
    printf '  (absent — nothing to reclaim)\n'
    return
  fi
  printf '  %-34s %8s\n' "total" "$(size_of "${TARGET_DIR}")"
  printf '  %-34s %8s\n' "debug/deps" "$(size_of "${TARGET_DIR}/debug/deps")"
  printf '  %-34s %8s\n' "debug/incremental" "$(size_of "${TARGET_DIR}/debug/incremental")"
  printf '  %-34s %8s\n' "debug/build" "$(size_of "${TARGET_DIR}/debug/build")"
  printf '  %-34s %8s\n' "files" "$(find "${TARGET_DIR}" -type f 2>/dev/null | wc -l | tr -d ' ')"
  if [[ -d "${TARGET_DIR}/debug/incremental" ]]; then
    printf '  note: incremental caches are the main grower; `CARGO_INCREMENTAL=0` skips them for one-off runs.\n'
  fi
}

report_backups() {
  local backups="${BACKEND_DIR}/backups"
  if [[ -d "${backups}" ]]; then
    printf '\ndev-reset backups/  %8s  (%s dirs; keep the newest before deleting)\n' \
      "$(size_of "${backups}")" "$(find "${backups}" -maxdepth 1 -type d -name 'reset-*' 2>/dev/null | wc -l | tr -d ' ')"
  fi
}

# Container writable-layer size as a whole number of gigabytes.
#
# Docker prints `601GB`, `20.5GB`, `1.2TB`, `500MB` …; a whole-number `GB`-only
# match silently skipped fractional and terabyte layers (review finding).
gigabytes_of() {
  printf '%s' "$1" | awk '
    match($0, /^[0-9.]+(kB|MB|GB|TB|B)/) {
      value = substr($0, 1, RLENGTH)
      unit = value
      gsub(/[0-9.]/, "", unit)
      gsub(/[a-zA-Z]/, "", value)
      if (unit == "TB") value = value * 1024
      else if (unit == "MB") value = value / 1024
      else if (unit == "kB") value = value / 1048576
      else if (unit == "B") value = 0
      printf "%d", value
    }
  '
}

report_docker() {
  command -v docker >/dev/null 2>&1 || return 0
  docker info >/dev/null 2>&1 || {
    printf '\ndocker: daemon not reachable (skipped)\n'
    return 0
  }

  printf '\ndocker\n'
  docker system df --format '{{.Type}}\t{{.Size}}\t{{.Reclaimable}}' 2>/dev/null |
    while IFS=$'\t' read -r type size reclaimable; do
      printf '  %-12s %-10s reclaimable: %s\n' "${type}" "${size}" "${reclaimable}"
    done

  # Containers with a huge writable layer: a client timeout leaves them running
  # and their copied tree is invisible to `du` on the host.
  docker ps -a --size --format '{{.ID}}\t{{.Image}}\t{{.Status}}\t{{.Size}}' 2>/dev/null |
    while IFS=$'\t' read -r id image status size; do
      local gigabytes
      gigabytes="$(gigabytes_of "${size}")"
      if [[ -n "${gigabytes}" && "${gigabytes}" -ge "${CONTAINER_WARN_GB}" ]]; then
        printf '  WARNING: container %s (%s, %s) has a %s writable layer — inspect and `docker rm -f` it\n' \
          "${id:0:12}" "${image}" "${status}" "${size}"
      fi
    done

  local stopped
  stopped="$(docker ps -aq --filter status=exited --filter status=created 2>/dev/null | wc -l | tr -d ' ')"
  printf '  %-34s %s\n' "stopped containers" "${stopped}"
  if [[ "${with_docker}" -eq 1 ]]; then
    if [[ "${apply}" -eq 1 ]]; then
      log "pruning stopped containers (testcontainers leftovers)"
      docker container prune -f >/dev/null
    else
      log "would prune ${stopped} stopped container(s) (docker container prune)"
    fi
    printf '  note: docker volumes are NOT pruned here — the dev stack data lives in them.\n'
  elif [[ "${stopped}" != "0" ]]; then
    printf '  pass --with-docker to prune stopped containers\n'
  fi
}

sweep() {
  [[ -d "${TARGET_DIR}" ]] || {
    log "target/ is absent — nothing to sweep"
    return 0
  }

  if ! cargo sweep --version >/dev/null 2>&1; then
    printf '\n'
    # Precise wording: `report_docker` may already have pruned containers, so
    # "nothing was deleted" would be false (review finding).
    log "cargo-sweep is not installed — no build artifacts were deleted"
    if [[ "${with_docker}" -eq 1 && "${apply}" -eq 1 ]]; then
      printf '  (stopped containers were pruned above; the target/ artifacts were left alone)\n'
    fi
    printf '  install it with: cargo install cargo-sweep --locked --version 0.8.0\n'
    printf '  (or compare against `cargo clean`, which removes ALL artifacts)\n'
    # A report run stays a successful report; `--apply` must fail, otherwise a
    # wrapper script cannot tell "not installed" from "nothing to do".
    if [[ "${apply}" -eq 1 ]]; then
      return 1
    fi
    return 0
  fi

  local sweep_args=()
  if [[ -n "${maxsize}" ]]; then
    sweep_args=(--maxsize "${maxsize}")
  else
    sweep_args=(--time "${days}")
  fi
  if [[ "${apply}" -eq 0 ]]; then
    sweep_args+=(--dry-run)
  fi

  log "cargo sweep ${sweep_args[*]} ${BACKEND_DIR}  (cargo-sweep $(cargo sweep --version 2>/dev/null | awk '{print $2}'))"
  local before after sweep_status=0
  before="$(size_of "${TARGET_DIR}")"
  # `cargo sweep` takes Cargo **project** paths and locates their target dir.
  # Its status is propagated: a failed sweep used to exit 0 because the closing
  # `printf` became the function's status (review finding).
  ( cd "${BACKEND_DIR}" && cargo sweep "${sweep_args[@]}" "${BACKEND_DIR}" ) || sweep_status=$?
  after="$(size_of "${TARGET_DIR}")"
  printf '  target/  %s → %s\n' "${before}" "${after}"
  if [[ "${sweep_status}" -ne 0 ]]; then
    printf '  WARNING: cargo sweep exited %s — the sweep did not complete\n' "${sweep_status}" >&2
  fi
  return "${sweep_status}"
}

printf '== breakdown-rs disk hygiene (%s) ==\n' "$([[ "${apply}" -eq 1 ]] && echo 'APPLY' || echo 'dry run — nothing is deleted')"
report_target
report_backups
# Reporting is best-effort: a docker hiccup must not abort the cargo sweep, the
# part of this script that actually reclaims space (review finding). `|| true`
# keeps errexit from firing inside the function as well.
report_docker || true

status=0
sweep || status=$?

if [[ "${apply}" -eq 1 ]]; then
  log "re-measure with: ./scripts/reclaim-disk.sh  (incremental caches regrow with every build)"
fi

printf '\nIf the disk is still tight, the heavier options are:\n'
printf '  cargo clean                        # remove ALL artifacts (a full rebuild follows)\n'
printf '  docker volume prune                # drops dev-stack data (postgres, sierradb) — deliberate only\n'
printf '  sudo btrfs balance start -musage=50 /   # metadata-chunk exhaustion on btrfs\n'
printf 'See backend/.github/instructions/build-performance.instructions.md.\n'

exit "${status}"
