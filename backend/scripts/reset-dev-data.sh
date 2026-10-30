#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0
# Copyright (C) 2024-2026 Breakdown RS Contributors
# Co-authored-by: glm-5.3 (neuralwatt)
#
# Dev data reset (issue #770) — wrapper around the `reset-dev-data` maintenance
# binary. See docs/operations/runbooks.md → "Dev data reset (issue #770)".
#
#   ./scripts/reset-dev-data.sh plan [--level imports|business]
#   ./scripts/reset-dev-data.sh imports [--dry-run] [--yes] [--no-backup]
#   ./scripts/reset-dev-data.sh business [--yes] [--no-backup] [--skip-volume-reset]
#   ./scripts/reset-dev-data.sh verify
#
# The binary does the database/event-store work; this script owns the three
# things a process cannot do for itself:
#   * stop/start the SierraDB container and drop its data volume (SierraDB 0.3.1
#     has no delete command at all — the volume is the only way to empty it),
#   * take the pg_dump and the volume tarball into the backup directory,
#   * check the API-level post-conditions (health, projector health).
#
# Never run this against anything but a local dev stack: the binary refuses
# non-loopback targets, non-development APP_ENV and REQUIRE_IN_TRANSIT_TLS, and
# this script refuses to touch a remote docker context.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKEND_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
COMPOSE_FILE="${BACKEND_DIR}/docker-compose.dev.yml"
API_HEALTH_URL="${API_HEALTH_URL:-http://127.0.0.1:3000/v1/health}"
PROJECTOR_HEALTH_URL="${PROJECTOR_HEALTH_URL:-http://127.0.0.1:3000/v1/ops/projector-health}"
SIERRADB_SERVICE="sierradb"
SIERRADB_DATA_DIR="/app/data"
SIERRADB_VOLUME_FALLBACK="backend_sierradb_dev_data"
POSTGRES_SERVICE="postgres"
POSTGRES_USER="${POSTGRES_USER:-postgres}"
POSTGRES_DB="${POSTGRES_DB:-breakdown}"

usage() {
  sed -n '6,19p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

die() {
  printf 'reset-dev-data: %s\n' "$1" >&2
  exit 1
}

log() {
  printf '==> %s\n' "$1"
}

# Loads the documented dev env files in the documented precedence order:
# `.env.local` first, then the generated overlays (`.env.dev-ai.local` carries
# the AI payload bucket + Vault, which the payload purge and the photo purge
# need; `.env.dev-vault.local` carries the Vault address/token on its own).
load_env() {
  local env_file
  set -a
  for env_file in "${BACKEND_DIR}/.env.local" \
                  "${BACKEND_DIR}/.env.dev-ai.local" \
                  "${BACKEND_DIR}/.env.dev-vault.local"; do
    if [[ -f "${env_file}" ]]; then
      # shellcheck disable=SC1090
      source "${env_file}"
    fi
  done
  set +a
  : "${DATABASE_URL:?DATABASE_URL is required (set it or provide backend/.env.local)}"
  : "${SIERRADB_URL:?SIERRADB_URL is required (set it or provide backend/.env.local)}"
}

# Refuses to operate on a remote docker context.
require_local_docker() {
  local context
  context="$(docker context show 2>/dev/null || echo default)"
  case "${context}" in
    default|desktop-linux|colima|orbstack) ;;
    *) die "docker context '${context}' is not a local context — refusing to reset a remote stack" ;;
  esac
}

compose() {
  docker compose -f "${COMPOSE_FILE}" "$@"
}

sierradb_volume() {
  local container volume
  container="$(compose ps -q "${SIERRADB_SERVICE}" 2>/dev/null || true)"
  if [[ -n "${container}" ]]; then
    volume="$(docker inspect -f "{{range .Mounts}}{{if eq .Destination \"${SIERRADB_DATA_DIR}\"}}{{.Name}}{{end}}{{end}}" "${container}" 2>/dev/null || true)"
  fi
  printf '%s' "${volume:-${SIERRADB_VOLUME_FALLBACK}}"
}

api_is_running() {
  curl -fsS -o /dev/null --max-time 2 "${API_HEALTH_URL}" 2>/dev/null
}

# Polls a TCP endpoint until it accepts connections (max 60 s).
wait_for_tcp() {
  local host="$1"
  local port="$2"
  local attempt
  for attempt in $(seq 1 60); do
    if (exec 3<>"/dev/tcp/${host}/${port}") 2>/dev/null; then
      return 0
    fi
    sleep 1
  done
  return 1
}

# The export phase reads both tiers, so they must accept connections - a
# previously aborted run leaves sierradb stopped on purpose (the volume drop
# stops it), and `compose up` alone is not enough because the containers are
# "running" before they are ready.
require_stack_running() {
  compose up -d "${POSTGRES_SERVICE}" "${SIERRADB_SERVICE}" >/dev/null
  local url="${SIERRADB_URL#*://}"
  url="${url%%/*}"
  url="${url##*@}"
  local host="${url%%:*}"
  local port="${url##*:}"
  if [[ "${port}" == "${host}" ]]; then
    port=9090
  fi
  wait_for_tcp "${host}" "${port}" \
    || die "SierraDB is not accepting connections at ${host}:${port}"
  compose exec -T "${POSTGRES_SERVICE}" \
    pg_isready -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" >/dev/null 2>&1 \
    || die "Postgres is not ready"
}

require_api_stopped() {
  if api_is_running; then
    die "the API is still running (${API_HEALTH_URL} answers) — stop it first: the projectors must not write during a reset"
  fi
}

run_binary() {
  ( cd "${BACKEND_DIR}" && cargo run --quiet -p api --bin reset-dev-data -- "$@" )
}

# Extracts --backup-dir from the forwarded arguments (default: newest reset dir).
resolve_backup_dir() {
  local dir=""
  local previous=""
  for arg in "$@"; do
    if [[ "${previous}" == "--backup-dir" ]]; then
      dir="${arg}"
    fi
    previous="${arg}"
  done
  if [[ -n "${dir}" ]]; then
    printf '%s' "${dir}"
    return
  fi
  local latest
  latest="$(ls -1dt "${BACKEND_DIR}"/backups/reset-* 2>/dev/null | head -n 1 || true)"
  [[ -n "${latest}" ]] || die "no backups/reset-* directory found — pass --backup-dir"
  printf '%s' "${latest}"
}

backup_postgres() {
  local backup_dir="$1"
  mkdir -p "${backup_dir}"
  log "pg_dump → ${backup_dir}/postgres.dump"
  compose exec -T "${POSTGRES_SERVICE}" \
    pg_dump -U "${POSTGRES_USER}" "${POSTGRES_DB}" > "${backup_dir}/postgres.dump"
}

backup_event_store() {
  local backup_dir="$1"
  local volume="$2"
  mkdir -p "${backup_dir}"
  log "SierraDB volume ${volume} → ${backup_dir}/sierradb-data.tgz"
  docker run --rm -v "${volume}:/data:ro" -v "${backup_dir}:/backup" alpine:3.20 \
    tar czf "/backup/sierradb-data.tgz" -C /data .
}

# Reports every container that still references the volume, so a failed removal
# names the blocker instead of printing a bare container id.
volume_users() {
  local volume="$1"
  docker ps -a --filter "volume=${volume}" \
    --format '{{.Names}} ({{.Status}})' 2>/dev/null | paste -sd ', ' -
}

reset_event_store() {
  local volume="$1"
  local users

  log "stopping ${SIERRADB_SERVICE}"
  compose stop "${SIERRADB_SERVICE}"

  # Docker refuses to remove a volume that ANY container references - including
  # an exited one. The stopped sierradb container itself keeps the reference, so
  # the container has to go before the volume can.
  log "removing the stopped ${SIERRADB_SERVICE} container (it still references the volume)"
  compose rm -f "${SIERRADB_SERVICE}" >/dev/null 2>&1 || true

  users="$(volume_users "${volume}")"
  if [[ -n "${users}" ]]; then
    die "volume ${volume} is still referenced by: ${users} - remove those containers first"
  fi

  if docker volume inspect "${volume}" >/dev/null 2>&1; then
    log "removing volume ${volume} (SierraDB 0.3.1 cannot delete events)"
    if ! docker volume rm "${volume}" >/dev/null; then
      die "could not remove volume ${volume} (referenced by: $(volume_users "${volume}"))"
    fi
  else
    log "volume ${volume} is already gone"
  fi

  log "starting ${SIERRADB_SERVICE} (compose recreates the volume)"
  compose up -d "${SIERRADB_SERVICE}"
  local attempt
  for attempt in $(seq 1 30); do
    if compose ps --status running -q "${SIERRADB_SERVICE}" | grep -q .; then
      sleep 1
      return 0
    fi
    sleep 1
  done
  die "${SIERRADB_SERVICE} did not come back up"
}

check_api_postconditions() {
  if ! api_is_running; then
    log "API not reachable at ${API_HEALTH_URL} — start it, then re-run: $0 verify"
    return 0
  fi

  local status
  log "GET ${PROJECTOR_HEALTH_URL}"
  status="$(curl -s -o /tmp/reset-dev-data-projector-health.json -w '%{http_code}' \
    --max-time 5 "${PROJECTOR_HEALTH_URL}" || echo 000)"
  case "${status}" in
    2*)
      cat /tmp/reset-dev-data-projector-health.json
      printf '\n'
      ;;
    403)
      # Deployment-scoped ops surface (issue #409): a dev user without an
      # ops_admin membership is denied. That is not a reset failure — point at
      # the knob instead of failing the run.
      log "projector health is authz-gated for this user (403)"
      log "  set OPS_ADMIN_SUBS=<sub> and restart the API to include the check"
      ;;
    000)
      die "projector health endpoint did not answer (${PROJECTOR_HEALTH_URL})"
      ;;
    *)
      die "projector health answered ${status}: $(cat /tmp/reset-dev-data-projector-health.json 2>/dev/null)"
      ;;
  esac
}

cmd_plan() {
  local level="imports"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --level) level="${2:?--level requires a value}"; shift 2 ;;
      *) die "unknown argument for plan: $1" ;;
    esac
  done
  run_binary --level "${level}" --phase "$([[ "${level}" == "business" ]] && echo export || echo all)" \
    --dry-run --env dev
}

cmd_imports() {
  run_binary --level imports --env dev "$@"
}

cmd_verify() {
  # `verify` is read-only; it must not stop to ask for a confirmation.
  run_binary --level business --phase verify --env dev --yes "$@"
  check_api_postconditions
}

cmd_business() {
  local assume_yes=0
  local backup=1
  local skip_volume_reset=0
  local passthrough=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --yes) assume_yes=1; passthrough+=("$1"); shift ;;
      --no-backup) backup=0; passthrough+=("$1"); shift ;;
      --skip-volume-reset) skip_volume_reset=1; shift ;;
      --backup-dir) passthrough+=("$1" "${2:?--backup-dir requires a path}"); shift 2 ;;
      *) die "unknown argument for business: $1" ;;
    esac
  done

  load_env
  require_local_docker
  require_api_stopped
  require_stack_running

  if [[ "${assume_yes}" -ne 1 ]]; then
    printf 'This wipes ALL business data of %s and drops the SierraDB volume.\n' "${DATABASE_URL%%\?*}"
    printf 'Configuration (ai_config, settings, membership) is exported and replayed.\n'
    read -r -p 'Type "business" to continue: ' typed
    [[ "${typed}" == "business" ]] || die "aborted"
    passthrough+=("--yes")
  fi

  local volume
  volume="$(sierradb_volume)"

  log "phase export (API stopped, keep-list captured)"
  run_binary --level business --phase export --env dev "${passthrough[@]}"

  local backup_dir
  backup_dir="$(resolve_backup_dir "${passthrough[@]}")"
  if [[ "${backup}" -eq 1 ]]; then
    backup_postgres "${backup_dir}"
    backup_event_store "${backup_dir}" "${volume}"
  else
    log "--no-backup: skipping pg_dump and the volume tarball"
  fi

  if [[ "${skip_volume_reset}" -eq 1 ]]; then
    log "--skip-volume-reset: keeping the existing event store"
  else
    reset_event_store "${volume}"
  fi

  # The operator confirmed the whole business flow once; every phase runs under
  # that confirmation (re-prompting per phase would also break --yes runs).
  log "phase wipe (read model + business buckets; event store must be empty)"
  run_binary --level business --phase wipe --env dev --backup-dir "${backup_dir}" --yes

  log "phase replay (keep-list back into the fresh event store)"
  run_binary --level business --phase replay --env dev --backup-dir "${backup_dir}" --yes

  cat <<EOF

==> next steps
  1. start the API:      (cd ${BACKEND_DIR} && set -a && source .env.local && set +a && cargo run -p api)
  2. wait for /v1/health, then:  $0 verify --backup-dir ${backup_dir}
  3. re-upload a previously imported document — it must answer 202 with a NEW job id
EOF
}

main() {
  local command="${1:-}"
  [[ $# -gt 0 ]] && shift
  case "${command}" in
    plan) cmd_plan "$@" ;;
    imports) load_env; cmd_imports "$@" ;;
    business) cmd_business "$@" ;;
    verify) load_env; cmd_verify "$@" ;;
    -h|--help|help|"") usage ;;
    *) die "unknown command '${command}' (expected plan|imports|business|verify)" ;;
  esac
}

main "$@"
