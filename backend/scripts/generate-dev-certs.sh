#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0
# Copyright (C) 2024-2026 Breakdown RS Contributors
# Co-authored-by: gpt-5.6-luna (opencode-go)

# Generate the dev CA + leaf certs for the local IdP (Logto) and API.
#
# Produces under backend/dev-certs/:
#   - ca.pem / ca.key        : self-signed dev CA (the single pinned trust anchor)
#   - idp.pem / idp.key      : leaf cert for localhost + 10.0.2.2 (Logto :3301)
#   - api.pem / api.key      : leaf cert for localhost + 10.0.2.2 (API :3000)
#
# The same CA signs both leaf certs — the Flutter client pins ca.pem and
# trusts both hosts (D1 primary of the `wire-flutter-oidc-auth` change).
#
# Idempotent: re-running overwrites the generated files. Safe to call from
# docker-compose.dev.yml init or by hand (`./scripts/generate-dev-certs.sh`).

set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
CERT_DIR="${REPO_ROOT}/dev-certs"
DAYS_VALID=3650

mkdir -p "${CERT_DIR}"

# 1) Dev CA ---------------------------------------------------------------
if [ ! -f "${CERT_DIR}/ca.key" ]; then
  openssl genrsa -out "${CERT_DIR}/ca.key" 4096 >/dev/null 2>&1
fi
openssl req -x509 -new -nodes \
  -key "${CERT_DIR}/ca.key" \
  -sha256 \
  -days "${DAYS_VALID}" \
  -subj "/CN=breakdown-dev-ca/O=Breakdown RS" \
  -out "${CERT_DIR}/ca.pem" >/dev/null 2>&1

# 2) Leaf cert helper -----------------------------------------------------
# Args: $1 = base name (idp|api), $2 = CN
generate_leaf() {
  local name="$1"
  local cn="$2"
  local key="${CERT_DIR}/${name}.key"
  local csr="${CERT_DIR}/${name}.csr"
  local cert="${CERT_DIR}/${name}.pem"
  local ext="${CERT_DIR}/${name}.ext"

  openssl genrsa -out "${key}" 2048 >/dev/null 2>&1

  # SAN: localhost, 127.0.0.1, 10.0.2.2 (Android emulator host loopback), ::1
  cat > "${ext}" <<EOF
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage = digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment
subjectAltName = @alt_names
[alt_names]
DNS.1 = localhost
IP.1 = 127.0.0.1
IP.2 = 10.0.2.2
IP.3 = ::1
EOF

  openssl req -new \
    -key "${key}" \
    -subj "/CN=${cn}/O=Breakdown RS" \
    -out "${csr}" >/dev/null 2>&1

  openssl x509 -req \
    -in "${csr}" \
    -CA "${CERT_DIR}/ca.pem" \
    -CAkey "${CERT_DIR}/ca.key" \
    -CAcreateserial \
    -out "${cert}" \
    -days "${DAYS_VALID}" \
    -sha256 \
    -extfile "${ext}" >/dev/null 2>&1

  rm -f "${csr}" "${ext}"
}

generate_leaf "idp" "localhost"
generate_leaf "api" "localhost"

# Restrict key permissions (defensive — these are dev-only certs).
chmod 600 "${CERT_DIR}"/*.key
chmod 644 "${CERT_DIR}"/*.pem

echo "Dev certs generated in ${CERT_DIR}:"
echo "  ca.pem / ca.key   — dev CA (pin this in the Flutter client)"
echo "  idp.pem / idp.key — Logto HTTPS (localhost, 10.0.2.2)"
echo "  api.pem / api.key — API HTTPS (localhost, 10.0.2.2)"
