#!/usr/bin/env sh
# SPDX-License-Identifier: AGPL-3.0
# Copyright (C) 2024-2026 Breakdown RS Contributors
# Co-authored-by: gpt-5.6-luna (opencode-go)
# Co-authored-by: deepseek-v4-flash (opencode-go)

# Certificate provision loop for the internal TLS mesh (ADR-024 / issue #156).
#
# Runs inside the `tls-provision` compose service (smallstep/step-ca image).
# On boot it copies the step-ca root into the shared `tls_data` volume and
# issues short-TTL leaf certificates (postgres, stunnel, caddy, vault) signed by the
# internal CA; then it keeps re-issuing on a `TLS_RENEW_INTERVAL` loop so
# certs rotate automatically (old certs stay valid for `TLS_CERT_TTL`, so
# servers that load their cert at startup keep serving a trusted chain until
# the operator restarts/reloads them — rotation never breaks clients).
#
# The step-ca volume (`step_ca_data`) is mounted read-only at /home/step so
# this loop can read the root/intermediate without holding the CA password.
# The admin provisioner password is supplied via STEP_CA_PASSWORD (the only
# allowed .env bootstrap secret, ADR-027).

set -eu

CA_URL="${CA_URL:-https://step-ca:9000}"
PROVISIONER="${PROVISIONER:-admin}"
TLS_CERT_TTL="${TLS_CERT_TTL:-24h}"
TLS_RENEW_INTERVAL="${TLS_RENEW_INTERVAL:-12h}"
PASSWORD_FILE="/run/secrets/step-ca-password"
# Docker-internal mesh certs; world-readable so the postgres/stunnel images
# (non-root users) can read them without chown gymnastics. The files live on
# the encrypted tls_data volume (ADR-023) and are short-TTL.
CERT_MODE=644

# --- prepare the provisioner password file ---
umask 077
mkdir -p "$(dirname "${PASSWORD_FILE}")"
printf '%s' "${STEP_CA_PASSWORD}" > "${PASSWORD_FILE}"
chmod 600 "${PASSWORD_FILE}"

# --- wait for step-ca and copy the root into the shared volume ---
echo "Waiting for step-ca to initialise..."
for _ in $(seq 1 90); do
    if [ -f /home/step/certs/root_ca.crt ]; then
        cp /home/step/certs/root_ca.crt /tls/root_ca.crt
        chmod "${CERT_MODE}" /tls/root_ca.crt
        break
    fi
    sleep 2
done
if [ ! -f /tls/root_ca.crt ]; then
    echo "ERROR: step-ca root_ca.crt never appeared in /home/step/certs" >&2
    exit 1
fi

# Wait until the CA answers so the very first issuance does not race step-ca.
for _ in $(seq 1 60); do
    if step ca health --ca-url "${CA_URL}" --root /tls/root_ca.crt >/dev/null 2>&1; then
        break
    fi
    sleep 2
done

issue() {
    subject="$1"
    echo "Issuing ${TLS_CERT_TTL} certificate for ${subject}..."
    step ca certificate "${subject}" "/tls/${subject}.crt" "/tls/${subject}.key" \
        --force \
        --ca-url "${CA_URL}" \
        --root /tls/root_ca.crt \
        --provisioner "${PROVISIONER}" \
        --provisioner-password-file "${PASSWORD_FILE}" \
        --not-after "${TLS_CERT_TTL}" \
        --san "${subject}" \
        --san localhost
    # `step ca certificate` writes leaf + intermediate chain into the .crt,
    # which is what the TLS servers need to present a verifiable chain.
    chmod 644 "/tls/${subject}.crt"
    # Private keys: tighten per consumer.
    #  - postgres:16-alpine runs ssl as uid/gid 70 and refuses group/world
    #    access; root-owned 0640 with group postgres satisfies its check
    #    ("u=rw,g=r … if owned by root").
    #  - stunnel/caddy run as root in their containers: 0600.
    case "${subject}" in
        postgres) chown 0:70 "/tls/${subject}.key" && chmod 640 "/tls/${subject}.key" ;;
        vault)    chown 100:1000 "/tls/${subject}.key" && chmod 640 "/tls/${subject}.key" ;;
        *)        chmod 600 "/tls/${subject}.key" ;;
    esac
}

# Issue once so dependent services can start (postgres/stunnel/caddy/vault gate on
# `tls-provision` becoming healthy, which checks these files exist).
issue postgres
issue stunnel
issue caddy
issue vault

while true; do
    echo "Sleeping ${TLS_RENEW_INTERVAL} before re-issuing certificates..."
    sleep "${TLS_RENEW_INTERVAL}"
    issue postgres
    issue stunnel
    issue caddy
    issue vault
done
