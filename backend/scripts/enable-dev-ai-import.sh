#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0
# Copyright (C) 2024-2026 Breakdown RS Contributors
# Co-authored-by: omen-alpha (opencode-go)

set -euo pipefail

# One-command AI-import enablement for the host-run dev API (issue #428/#468).
#
# A `cargo run --bin api` started on the host cannot reach the internal-only
# dev Garage, and `AI_IMPORT_ENABLED=1` fails closed (#181 — no in-memory
# payload fallback) until durable payload storage is configured. The settings /
# AI-config credential flow additionally needs a reachable Vault (ADR-027),
# and the dev user needs an active credential role to reach the AUTHZ-GATED
# endpoints. This script performs the whole sequence:
#
#   1. Enables the Vault overlay (scripts/enable-dev-vault.sh + the
#      docker-compose.dev.vault.yml overlay), publisher of Vault's HTTP API on
#      loopback 127.0.0.1:8200 — dev-only plaintext, same `vault-bootstrap`
#      one-shot + `breakdown-app` policy as prod.
#   2. Boots the dev compose with the AI + Vault overlays
#      (docker-compose.dev.ai.yml publishes Garage's S3 (:3900) and admin
#      (:3902) ports to the host).
#   3. Provisions Garage: cluster layout, the costume-photos bucket (ADR-019)
#      and the ai-import-payloads bucket, plus a fixed dev-only S3 key.
#   4. Verifies the Garage + Vault ports are reachable from the host.
#   5. Writes `.env.dev-ai.local` (git-ignored, chmod 600) with the complete
#      host-run env: AI_IMPORT_ENABLED + AI_PAYLOAD_S3_* + VAULT_ADDR +
#      VAULT_APP_TOKEN_FILE + DB/SierraDB.
#
# Usage (from `backend/`):
#   ./scripts/enable-dev-ai-import.sh            # boot + provision + env file
#   ./scripts/enable-dev-ai-import.sh --run      # also start the API + bootstrap
#                                                 # the dev credential role afterwards
#
# The script is idempotent: Garage roles are only assigned when missing,
# bucket/key creation errors on "already exists" are tolerated, Vault re-runs
# renew the app token, and the env file is rewritten with the same
# deterministic values.
#
# Dev-only credentials: the S3 access key and secret are derived
# deterministically from fixed dev-only strings (gitleaks-clean derivation —
# no high-entropy literal is committed). Never reuse these outside a local
# dev Garage; production provisiones real keys via the ops runbook.

cd "$(dirname "$0")/.."

COMPOSE_ARGS=(-f docker-compose.dev.yml -f docker-compose.dev.ai.yml -f docker-compose.dev.vault.yml)
ADMIN_TOKEN="${GARAGE_ADMIN_TOKEN:-garage_admin_dev}"
ENV_FILE=".env.dev-ai.local"

# Deterministic dev-only S3 credentials (see header note).
ACCESS_KEY="GK$(printf 'breakdown-dev-only-s3-key-id' | sha256sum | cut -c1-24)"
SECRET_KEY="$(printf 'breakdown-dev-only-s3-secret' | sha256sum | cut -d' ' -f1)"

echo "==> Ensuring dev Vault state + bootstrap token (.vault-dev/)"
# Must exist before ANY compose up with the Vault overlay: the
# vault-bootstrap one-shot mounts its dev-only bootstrap secret from here.
VAULT_DIR=".vault-dev"
mkdir -p "$VAULT_DIR" "$VAULT_DIR/unseal" "$VAULT_DIR/app-token"
umask 077
if [ ! -s "$VAULT_DIR/bootstrap.token" ]; then
    # Dev-only recovery seed for vault-bootstrap.sh; random so it is never
    # mistaken for a real secret. Git-ignored via .vault-dev/.
    head -c 32 /dev/urandom | base64 > "$VAULT_DIR/bootstrap.token"
fi
chmod 600 "$VAULT_DIR/bootstrap.token"
umask 022

echo "==> Booting dev runtime with AI + Vault overlay (Garage ports published to host)"
# Explicit service list: the vault-bootstrap one-shot is driven via `run --rm`
# below (same compose invocation set), so no container is ever started against
# a silently-torn-down network from a different file set (issue #468).
docker compose "${COMPOSE_ARGS[@]}" up -d postgres sierradb garage-config garage vault

echo "==> Running Vault bootstrap (init/unseal/engines/policy/app-token)"
docker compose "${COMPOSE_ARGS[@]}" run --rm vault-bootstrap

# Shared post-provision step (ownership, reachability, .env.dev-vault.local) —
# no docker calls, so the combined compose invocation set stays the single
# source of truth for the project's containers/networks (issue #468).
./scripts/enable-dev-vault.sh --finalize

# Re-render the Garage config one-shot and restart Garage against it, so the
# rendered TOML always matches the current dev defaults.
docker compose "${COMPOSE_ARGS[@]}" up -d --force-recreate garage-config garage

echo "==> Waiting for Garage to become healthy"
for _ in $(seq 1 30); do
    if [ "$(docker inspect --format='{{.State.Health.Status}}' "$(docker compose "${COMPOSE_ARGS[@]}" ps -q garage)")" = "healthy" ]; then
        break
    fi
    sleep 2
done

# Run the Garage CLI inside the (bare-binary) garage container against its own
# config + admin token. Each call is a direct exec — the image has no shell.
gcli() {
    docker compose "${COMPOSE_ARGS[@]}" exec -T garage \
        /garage -c /etc/garage/config.toml --admin-token "$ADMIN_TOKEN" "$@"
}

echo "==> Ensuring Garage cluster layout (single-node, dev)"
if gcli status 2>/dev/null | grep -q "NO ROLE ASSIGNED"; then
    # Node line sits BELOW the column-header row ("ID  Hostname  ..."); skip
    # both the section header and that header line, then take the first line
    # whose first field is a hex Garage node id (short id, length ≥ 16).
    NODE_ID="$(gcli status 2>/dev/null | awk '/==== HEALTHY NODES ====/{h=1;next} h && $1 ~ /^[0-9a-f]{16,64}$/ {print $1; exit}')"
    if [ -z "$NODE_ID" ]; then
        echo "ERROR: could not parse Garage node id from 'garage status'" >&2
        gcli status >&2 || true
        exit 1
    fi
    gcli layout assign -z dc1 -c 1G "$NODE_ID"
    # After `layout assign`, Garage enacts the STAGED changes at version
    # current + 1 — applying the current version fails with
    # "Invalid new layout version".
    CURRENT="$(gcli layout show 2>/dev/null | sed -n 's/^Current cluster layout version: //p')"
    if ! [[ "$CURRENT" =~ ^[0-9]+$ ]]; then
        echo "ERROR: could not parse Garage layout version from 'garage layout show'" >&2
        exit 1
    fi
    gcli layout apply --version "$((CURRENT + 1))"
else
    echo "    Cluster layout already assigned — skipping"
fi

echo "==> Provisioning buckets + S3 key (dev)"
# Idempotency: existing buckets/keys error out on re-create; that is the
# expected path on re-runs, matching scripts/provision-garage.sh behavior.
gcli bucket create costume-photos 2>/dev/null || true
gcli bucket create ai-import-payloads 2>/dev/null || true
gcli key import "$ACCESS_KEY" "$SECRET_KEY" -n breakdown-api --yes 2>/dev/null || true
for bucket in costume-photos ai-import-payloads; do
    gcli bucket allow --read --write --owner "$bucket" --key "$ACCESS_KEY" >/dev/null
done

echo "==> Verifying host reachability"
if ! curl -sf http://localhost:3902/v1/status \
        -H "Authorization: Bearer $ADMIN_TOKEN" >/dev/null; then
    echo "Garage admin API not reachable on localhost:3902" >&2
    exit 1
fi
# Any HTTP answer (403 unauthenticated included) proves the S3 port is open.
if ! curl -s -o /dev/null http://localhost:3900/; then
    echo "Garage S3 API not reachable on localhost:3900" >&2
    exit 1
fi
echo "    S3 (localhost:3900) and admin API (localhost:3902) reachable"

echo "==> Writing $ENV_FILE"
umask 077
cat > "$ENV_FILE" <<EOF
# Generated by scripts/enable-dev-ai-import.sh (issue #428). Git-ignored.
# AI import with durable Garage payload storage for the host-run dev API.
AI_IMPORT_ENABLED=1
AI_PAYLOAD_S3_ENDPOINT=http://localhost:3900
AI_PAYLOAD_S3_ACCESS_KEY=$ACCESS_KEY
AI_PAYLOAD_S3_SECRET_KEY=$SECRET_KEY
AI_PAYLOAD_S3_BUCKET=ai-import-payloads
DATABASE_URL=postgres://postgres:postgres@localhost:5432/breakdown
SIERRADB_URL=redis://127.0.0.1:9090/?protocol=resp3
# Dev Vault (issue #468) — merged from scripts/enable-dev-vault.sh.
VAULT_ADDR=$(sed -n 's/^VAULT_ADDR=//p' .env.dev-vault.local)
VAULT_APP_TOKEN_FILE=$(sed -n 's/^VAULT_APP_TOKEN_FILE=//p' .env.dev-vault.local)
EOF
chmod 600 "$ENV_FILE"

echo ""
if [ -s "$ENV_FILE" ] && grep -q '^VAULT_APP_TOKEN_FILE=' "$ENV_FILE"; then
    vault_status="Vault: $(grep '^VAULT_ADDR=' "$ENV_FILE" | cut -d= -f2)"
else
    vault_status="Vault: NOT configured"
fi
echo "AI import is enabled for the host-run dev API ($vault_status)."
echo ""
echo "Start the API with:"
echo "  set -a; . ./$ENV_FILE; set +a; cargo run -p api"
echo "(or re-run this script with --run to start the API and bootstrap the"
echo " dev credential role for DEV_AUTH_SUB automatically)"

if [ "${1:-}" = "--run" ]; then
    echo ""
    echo "==> Starting the API (AI import + Vault enabled, dev auth)"
    set -a
    # Canonical dev env (DEV_AUTH_SUB / DEV_AUTH_EMAIL / optional overrides).
    # shellcheck disable=SC1090
    if [ -f .env.local ]; then
        . ./.env.local
    fi
    # shellcheck disable=SC1090
    . "$ENV_FILE"
    set +a
    : "${DEV_AUTH_SUB:?DEV_AUTH_SUB is required for the host-run dev API (set it in .env.local or the environment)}"
    API_URL="${API_URL:-http://127.0.0.1:3000}"

    echo "==> Starting the API in the background, then bootstrapping the dev credential role"
    cargo run -p api &
    API_PID=$!
    trap 'kill "$API_PID" 2>/dev/null || true' EXIT

    up=0
    for _ in $(seq 1 180); do
        if curl -fsS "$API_URL/api-docs/openapi.json" -o /dev/null 2>/dev/null; then
            up=1
            break
        fi
        if ! kill -0 "$API_PID" 2>/dev/null; then
            echo "ERROR: the API process exited before becoming ready" >&2
            wait "$API_PID" || true
            exit 1
        fi
        sleep 1
    done
    if [ "$up" != "1" ]; then
        echo "ERROR: API did not become ready on $API_URL within 180s" >&2
        wait "$API_PID" || true
        exit 1
    fi

    echo "==> Bootstrapping the dev credential role (block → CostumeAssistant)"
    if DEV_AUTH_SUB="$DEV_AUTH_SUB" API_URL="$API_URL" \
        ./scripts/bootstrap-dev-credential-role.sh; then
        :
    else
        echo "WARN: credential-role bootstrap failed — re-run ./scripts/bootstrap-dev-credential-role.sh against the running API" >&2
    fi

    # Keep the API in the foreground (Ctrl-C stops both).
    wait "$API_PID" || true
fi
