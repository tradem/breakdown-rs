#!/bin/sh
# SPDX-License-Identifier: AGPL-3.0
# Copyright (C) 2024-2026 Breakdown RS Contributors
# Co-authored-by: gpt-5.6-luna (opencode-go)
# Co-authored-by: glm-5.2 (neuralwatt)

# Idempotent first-boot bootstrap for the internal Vault service.
# VAULT_BOOTSTRAP_TOKEN is supplied only to this one-shot container. It is a
# recovery seed for an already-initialized Vault; the API never receives it.
set -eu

: "${VAULT_ADDR:=http://vault:8200}"
: "${VAULT_BOOTSTRAP_TOKEN:?VAULT_BOOTSTRAP_TOKEN is required}"
export VAULT_ADDR

bootstrap_dir=/vault/data/bootstrap
unseal_file="$bootstrap_dir/unseal.key"
token_file=/vault/app-token/app.token
mkdir -p "$bootstrap_dir" /vault/app-token
chmod 700 "$bootstrap_dir"
# The API image uses uid 1000 and receives only this separate token volume.
chown 1000:1000 /vault/app-token
chmod 700 /vault/app-token

status=255
attempt=0
while [ "$attempt" -lt 60 ]; do
  set +e
  vault status >/dev/null 2>&1
  status=$?
  set -e
  # 0 = initialized/unsealed, 1 = initialized/sealed, 2 = uninitialized.
  if [ "$status" -eq 0 ] || [ "$status" -eq 1 ] || [ "$status" -eq 2 ]; then
    break
  fi
  attempt=$((attempt + 1))
  sleep 2
done

initialized_now=0
root_token="${VAULT_BOOTSTRAP_TOKEN}"
if [ "$status" -eq 2 ]; then
  # Vault 1.20 generates the initial root token; it no longer accepts a
  # caller-supplied -root-token. The generated token is used in-memory only
  # and revoked after policy/app-token provisioning below.
  init_json=$(vault operator init -key-shares=1 -key-threshold=1 -format=json)
  init_one_line=$(printf '%s' "$init_json" | tr '\n' ' ')
  unseal_key=$(printf '%s' "$init_one_line" | sed -n 's/.*"unseal_keys_b64"[[:space:]]*:[[:space:]]*\[[[:space:]]*"\([^"]*\)".*/\1/p')
  generated_root=$(printf '%s' "$init_one_line" | sed -n 's/.*"root_token"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
  if [ -z "$unseal_key" ] || [ -z "$generated_root" ]; then
    echo "Vault bootstrap failed: init returned incomplete key material" >&2
    exit 1
  fi
  umask 077
  printf '%s\n' "$unseal_key" > "$unseal_file"
  root_token="$generated_root"
  initialized_now=1
fi

if ! vault status >/dev/null 2>&1; then
  if [ ! -s "$unseal_file" ]; then
    echo "Vault bootstrap failed: sealed Vault has no persisted unseal key" >&2
    exit 1
  fi
  vault operator unseal "$(cat "$unseal_file")" >/dev/null
fi

# On normal restarts no root token is available or needed. Renew the existing
# app token and leave immediately; this preserves the root-token discard rule.
if [ "$initialized_now" -eq 0 ] && [ -s "$token_file" ]; then
  if VAULT_TOKEN=$(cat "$token_file") vault token lookup >/dev/null 2>&1; then
    VAULT_TOKEN=$(cat "$token_file") vault token renew >/dev/null 2>&1 || true
    unset VAULT_BOOTSTRAP_TOKEN VAULT_TOKEN
    echo "Vault already bootstrapped; app token renewed"
    exit 0
  fi
fi

# The generated root token (first boot), or the operator-provided recovery
# seed (a later repair), is used only for administrative bootstrap calls.
export VAULT_TOKEN="$root_token"
if ! vault token lookup >/dev/null 2>&1; then
  echo "Vault bootstrap failed: no usable administrative token" >&2
  exit 1
fi

if ! vault secrets list | grep -q '^transit/'; then
  vault secrets enable -path=transit transit >/dev/null
fi
if ! vault secrets list | grep -q '^kv/'; then
  vault secrets enable -path=kv -version=2 kv >/dev/null
fi

vault policy write breakdown-app - >/dev/null <<'POLICY'
path "transit/keys/settings-*" {
  capabilities = ["create", "read", "update", "delete"]
}
path "transit/datakey/plaintext/settings-*" {
  capabilities = ["update"]
}
path "transit/encrypt/settings-*" {
  capabilities = ["update"]
}
path "transit/decrypt/settings-*" {
  capabilities = ["update"]
}
path "transit/rewrap/settings-*" {
  capabilities = ["update"]
}
path "transit/keys/settings-*/config" {
  capabilities = ["update"]
}
path "kv/data/settings-secrets/*" {
  capabilities = ["create", "read", "update", "delete"]
}
path "kv/metadata/settings-secrets/*" {
  capabilities = ["read", "delete"]
}
POLICY

# Keep a short-lived, least-privilege token in a separate named volume. If the
# existing token is still valid, the restart path above renews it instead.
token_json=$(vault token create -orphan -policy=breakdown-app -period=24h -format=json)
app_token=$(printf '%s' "$token_json" | sed -n 's/.*"client_token"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
if [ -z "$app_token" ]; then
  echo "Vault bootstrap failed: app token was not created" >&2
  exit 1
fi
umask 077
tmp_token="$token_file.tmp"
printf '%s\n' "$app_token" > "$tmp_token"
chown 1000:1000 "$tmp_token"
chmod 600 "$tmp_token"
mv "$tmp_token" "$token_file"

# Revoke the administrative token and remove it from this process. The only
# surviving credential is the least-privilege app token in its own volume.
VAULT_TOKEN="$root_token" vault token revoke -self >/dev/null 2>&1 || true
unset VAULT_TOKEN VAULT_BOOTSTRAP_TOKEN root_token generated_root unseal_key init_json init_one_line app_token

echo "Vault bootstrap complete (Transit, KV-v2, and app policy ready)"
