#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0
# Copyright (C) 2024-2026 Breakdown RS Contributors
# Co-authored-by: deepseek-v4-flash (neuralwatt)

set -euo pipefail

# Grant the dev user the credential role so the AUTHZ-GATED settings and AI
# import endpoints (/settings/credentials, /v1/ai-import/config, ...) stop
# returning 403 (issue #468).
#
# The AI-config and settings handlers are gated by
# `has_active_credential_role` (an active CostumeDesigner|CostumeAssistant in
# any block). After a DB reset the dev user has no membership, and these
# handler-internal gates deliberately ignore AUTHZ_ENFORCE (which dev auth
# mode defaults OFF). The ADR-018/ADR-028-consistent way to become a
# credential member is the real membership path: `POST /v1/blocks` dispatches
# `BootstrapOwner`, which grants the block creator `Role::CostumeAssistant` —
# an active credential role. This script drives that sequence against a live
# dev-auth API:
#
#   series (fresh UUIDv7) → season → block  ⇒  dev user becomes CostumeAssistant
#
# Prerequisites: the API must be running in dev auth mode (`DEV_AUTH_SUB`),
# because the script relies on the dummy user (no bearer token needed) and the
# enforcement-off middleware. Idempotent: if the dev user already holds an
# active credential role it exits immediately with the role check skipped.
#
# Usage (from `backend/`, API already up):
#   DEV_AUTH_SUB=dev-user ./scripts/bootstrap-dev-credential-role.sh
#   API_URL=http://127.0.0.1:3000 DEV_AUTH_SUB=dev-user ./scripts/...  # custom port

cd "$(dirname "$0")/.."

API_URL="${API_URL:-http://127.0.0.1:3000}"
: "${DEV_AUTH_SUB:?DEV_AUTH_SUB is required (the dev-auth dummy user sub; set on the API boot + here)}"

# RFC 9562 UUIDv7 from /dev/urandom (dev-only helper — the server does not
# version-validate client-supplied ids, but staying v7 keeps ADR-004 semantics).
uuidv7() {
    local ms ms_hex rand r0 rv rb
    ms=$(( $(date +%s) * 1000 + 10#$(date +%N) / 1000000 ))
    ms_hex=$(printf '%012x' "$ms")
    rand=$(head -c 10 /dev/urandom | od -An -tx1 | tr -d ' \n')
    r0="${rand:0:3}"
    rv="${rand:3:1}"
    rb="${rand:4:15}"
    case "$rv" in 8|9|a|b) ;; *) rv=8 ;; esac
    printf '%s-%s-7%s-%s%s-%s\n' \
        "${ms_hex:0:8}" "${ms_hex:8:4}" "${r0}" "$rv" "${rb:0:3}" "${rb:3:12}"
}

json_id() {
    # Extract the `"id"` of a single JSON object response {"id":"...","version":N}.
    sed -n 's/.*"id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1
}

echo "==> Checking whether $DEV_AUTH_SUB already holds an active credential role"
code=$(curl -s -o /dev/null -w '%{http_code}' "$API_URL/v1/ai-import/config?limit=1")
if [ "$code" = "200" ]; then
    echo "    credential role already active — nothing to do"
    exit 0
fi
if [ "$code" != "403" ]; then
    echo "ERROR: unexpected status $code from GET $API_URL/v1/ai-import/config" >&2
    echo "       (expected 403 = no credential role, or 200 = already present)." >&2
    echo "       Is the API up and running in dev auth mode (DEV_AUTH_SUB)? See local-dev-runtime docs." >&2
    exit 1
fi

series_id=$(uuidv7)

echo "==> Creating season (series $series_id) and block to bootstrap membership"
season_json=$(curl -fsS -X POST "$API_URL/v1/seasons" \
    -H 'Content-Type: application/json' \
    -d "{\"series_id\":\"$series_id\",\"number\":1,\"title\":\"Dev AI import\"}")
season_id=$(printf '%s' "$season_json" | json_id)
if [ -z "$season_id" ]; then
    echo "ERROR: could not parse season id from: $(printf '%s' "$season_json" | head -c 200)" >&2
    exit 1
fi

# Creating a block dispatches BootstrapOwner → the creator (the dev-auth
# current user) becomes an active CostumeAssistant — a credential role.
block_json=$(curl -fsS -X POST "$API_URL/v1/blocks" \
    -H 'Content-Type: application/json' \
    -d "{\"season_id\":\"$season_id\",\"series_id\":\"$series_id\",\"number\":1}")
block_id=$(printf '%s' "$block_json" | json_id)
if [ -z "$block_id" ]; then
    echo "ERROR: could not parse block id from: $(printf '%s' "$block_json" | head -c 200)" >&2
    exit 1
fi

echo "    season=$season_id block=$block_id"

echo "==> Waiting for the membership projector (OwnerBootstrapped → CostumeAssistant)"
ok=0
for _ in $(seq 1 30); do
    code=$(curl -s -o /dev/null -w '%{http_code}' "$API_URL/v1/ai-import/config?limit=1")
    if [ "$code" = "200" ]; then
        ok=1
        break
    fi
    sleep 1
done
if [ "$ok" != "1" ]; then
    echo "ERROR: credential role not active after creating the block (last status $code)." >&2
    echo "       Check the API log for a failed BootstrapOwner / projector error." >&2
    exit 1
fi

echo ""
echo "Credential role active for $DEV_AUTH_SUB (CostumeAssistant via BootstrapOwner)."
echo "The AI-import config + settings credential endpoints are now reachable:"
echo "  curl $API_URL/v1/ai-import/config?limit=1"
