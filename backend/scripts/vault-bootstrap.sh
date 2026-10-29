#!/bin/sh
# SPDX-License-Identifier: AGPL-3.0
# Copyright (C) 2024-2026 Breakdown RS Contributors
# Co-authored-by: gpt-5.6-luna (opencode-go)
# Co-authored-by: glm-5.2 (neuralwatt)
# Co-authored-by: deepseek-v4-flash (neuralwatt)
# Co-authored-by: deepseek-v4.1-flash (opencode-go)

# Idempotent first-boot bootstrap for the internal Vault service.
# VAULT_BOOTSTRAP_TOKEN_FILE points to a Docker secret mounted only into this
# one-shot container. The API never receives the bootstrap seed.
#
# Repair path: the least-privilege app token is a 24 h *periodic* token, so it
# lapses whenever nothing renews it in time (the API down past the TTL, or the
# token revoked). Re-running this script then issues a fresh one. Because no
# administrative credential survives provisioning (the generated root token is
# revoked at the end), a repair mints a root token through `operator
# generate-root` from the persisted unseal share and revokes it again — Vault
# state (KV secrets, Transit keys, the photo SSE-C key) survives a repair,
# unlike a full `down -v` reset.
set -eu

: "${VAULT_ADDR:=https://vault:8200}"
# TLS is opt-in. Prod mounts the step-ca root at /tls/root_ca.crt and passes
# VAULT_CACERT; the dev overlay (docker-compose.dev.vault.yml, issue #468)
# serves plaintext HTTP and leaves it unset, so the same bootstrap drives both.
# Prod keeps its explicit VAULT_CACERT (→ https, unchanged); dev keeps the
# http:// scheme and no CA.
if [ -n "${VAULT_CACERT:-}" ]; then
  : # caller supplied an explicit CA path
elif [ -f /tls/root_ca.crt ]; then
  VAULT_CACERT=/tls/root_ca.crt
else
  unset VAULT_CACERT
fi
: "${VAULT_BOOTSTRAP_TOKEN_FILE:=/run/secrets/vault_bootstrap_token}"
if [ ! -r "$VAULT_BOOTSTRAP_TOKEN_FILE" ]; then
  echo "Vault bootstrap failed: bootstrap secret file is not readable" >&2
  exit 1
fi
VAULT_BOOTSTRAP_TOKEN=$(cat "$VAULT_BOOTSTRAP_TOKEN_FILE")
: "${VAULT_BOOTSTRAP_TOKEN:?VAULT_BOOTSTRAP_TOKEN is required}"
export VAULT_ADDR
if [ -n "${VAULT_CACERT:-}" ]; then
  export VAULT_CACERT
fi

bootstrap_dir=/vault/unseal/bootstrap
unseal_file="$bootstrap_dir/unseal.key"
token_file=/vault/app-token/app.token
mkdir -p "$bootstrap_dir" /vault/app-token
chmod 700 "$bootstrap_dir"
# The dev overlay bind-mounts /vault/unseal from the host; keep the unseal
# dir owned by the API uid (1000) like the app-token dir so a host user can
# read/reset it without root. Prod's named volume is unaffected.
chown 1000:1000 "$bootstrap_dir"
# The API image uses uid 1000 and receives only this separate token volume.
chown 1000:1000 /vault/app-token
chmod 700 /vault/app-token
# The unseal key is also the repair credential (`generate_root_token`), so it
# must be readable by the same non-root uid as the app token. Files written by
# earlier script versions were left root:root and blocked a host-side repair.
if [ -f "$unseal_file" ]; then
  chown 1000:1000 "$unseal_file"
fi

# BusyBox wget in the pinned Vault image has HTTPS support but no
# --ca-certificate option. Extend its container-local CA bundle with the
# public step-ca root; this does not modify the mounted host volume. The dev
# overlay is plaintext http:// and has no CA to append. Idempotent: the unseal
# and generate-root paths can both run in one invocation.
wget_ca_prepared=0
prepare_wget_ca() {
  if [ "$wget_ca_prepared" = "1" ]; then
    return 0
  fi
  if [ -n "${VAULT_CACERT:-}" ] && [ -f /etc/ssl/certs/ca-certificates.crt ]; then
    cat "$VAULT_CACERT" >> /etc/ssl/certs/ca-certificates.crt
  fi
  wget_ca_prepared=1
}

# Revoke a *generated* administrative token on every exit path.
#
# `set -e` can abort between minting the root token and the revoke in the
# provisioning tail (`secrets enable`, `policy write`, `token create`), and a
# generate-root token carries no guaranteed expiry — leaving one live would hand
# out an unowned root credential (the bootstrapped root token is discarded on
# purpose). A token *supplied* by the operator is deliberately not revoked here:
# it is the caller's credential and the retry material for the next run, so only
# `generate_root_token` sets the flag.
admin_token_generated=0
# Set while a `generate-root -init` attempt is open on the server.
generate_root_pending=0
# Accessor of the token this run minted, recorded before any command can fail so
# a later run can revoke a token whose shell died without running a trap.
admin_accessor_file="$bootstrap_dir/.generated-root-accessor"
revoke_generated_admin_token() {
  [ "$admin_token_generated" = "1" ] || return 0
  admin_token_generated=0
  if [ -z "${root_token:-}" ]; then
    return 0
  fi
  if VAULT_TOKEN="$root_token" vault token revoke -self >/dev/null 2>&1; then
    rm -f "$admin_accessor_file"
  else
    echo "Vault bootstrap warning: could not revoke the minted administrative token; revoke it manually" >&2
  fi
  return 0
}

# Abandon this invocation's in-flight generate-root attempt. Vault serializes
# root generation (`root generation already in progress`), so every failure
# return after a successful `-init` must cancel — otherwise the next repair run
# cannot even initialize until the stale attempt is cleared by hand. Retried
# because a single transient error would strand the attempt.
cancel_generate_root() {
  [ "$generate_root_pending" = "1" ] || return 0
  cancel_try=0
  while [ "$cancel_try" -lt 3 ]; do
    if vault operator generate-root -cancel >/dev/null 2>&1; then
      generate_root_pending=0
      return 0
    fi
    cancel_try=$((cancel_try + 1))
    sleep 1
  done
  return 1
}

cancel_pending_generate_root() {
  if ! cancel_generate_root; then
    echo "Vault bootstrap warning: could not cancel the in-flight generate-root attempt; clear it with 'vault operator generate-root -cancel'" >&2
  fi
  return 0
}

# One EXIT handler: an interrupted run must abandon its attempt *and* its token.
cleanup_on_exit() {
  cancel_pending_generate_root
  revoke_generated_admin_token
}
trap cleanup_on_exit EXIT
# A signal-killed one-shot would skip the EXIT trap entirely, so these three
# signals exit into it. SIGKILL cannot be trapped — see `record_admin_accessor`.
trap 'cancel_pending_generate_root; exit 130' INT
trap 'cancel_pending_generate_root; exit 143' TERM
trap 'cancel_pending_generate_root; exit 129' HUP

# Record the minted token's accessor in the bootstrap dir (600) before the next
# command runs. No trap survives SIGKILL, an OOM kill or host loss, and Vault
# would then hold a live root token nobody can name; the accessor is what a later
# run needs to revoke it. Best effort: the graceful paths revoke by token anyway.
record_admin_accessor() {
  [ "$admin_token_generated" = "1" ] || return 0
  accessor=$(VAULT_TOKEN="$root_token" vault token lookup -format=json 2>/dev/null \
    | tr '\n' ' ' \
    | sed -n 's/.*"accessor"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p') || accessor=
  if [ -z "$accessor" ]; then
    return 0
  fi
  (
    umask 077
    printf '%s\n' "$accessor" > "$admin_accessor_file"
  ) || return 0
}

# Revoke a token left behind by a run that died before its revoke. Vault answers
# an unknown accessor with a warning and no error, so this is idempotent and the
# record is dropped once the revoke is confirmed.
revoke_stale_admin_token() {
  if [ ! -s "$admin_accessor_file" ]; then
    return 0
  fi
  stale_accessor=$(cat "$admin_accessor_file") || stale_accessor=
  if [ -n "$stale_accessor" ] \
      && VAULT_TOKEN="$root_token" vault token revoke -accessor="$stale_accessor" >/dev/null 2>&1; then
    rm -f "$admin_accessor_file"
  fi
  return 0
}

# Mint a short-lived administrative token from the persisted unseal share.
#
# Required when the app token lapsed: Vault never revives an expired token, and
# the bootstrapped root token was discarded, so a repair has no administrative
# credential left. `operator generate-root` needs exactly what this container
# already holds — one unseal share (the init above uses 1/1). The share, the
# client-side OTP and the encoded token stay in shell variables and in 600
# request files; none of them is passed in argv (same rule as the unseal call
# below). Assigns `root_token` / `admin_token_generated` in the *caller's* shell
# and returns non-zero without a token: a minted token must reach the revoke trap
# before any further command can fail, which a command substitution would hide.
generate_root_token() {
  if [ ! -s "$unseal_file" ]; then
    return 1
  fi
  init_json=$(vault operator generate-root -init -format=json) || return 1
  # Vault now holds an open attempt that only a cancel (or a completed update)
  # releases; every later exit path must abandon it.
  generate_root_pending=1
  init_one_line=$(printf '%s' "$init_json" | tr '\n' ' ')
  nonce=$(printf '%s' "$init_one_line" | sed -n 's/.*"nonce"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
  otp=$(printf '%s' "$init_one_line" | sed -n 's/.*"otp"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
  if [ -z "$nonce" ] || [ -z "$otp" ]; then
    cancel_generate_root
    return 1
  fi
  prepare_wget_ca
  payload="$bootstrap_dir/.generate-root-request.$$"
  response="$bootstrap_dir/.generate-root-response.$$"
  (
    umask 077
    printf '{"key":"%s","nonce":"%s"}\n' "$(cat "$unseal_file")" "$nonce" > "$payload"
  ) || {
    cancel_generate_root
    return 1
  }
  if ! wget --quiet \
      --header='Content-Type: application/json' \
      --post-file="$payload" -O "$response" \
      "$VAULT_ADDR/v1/sys/generate-root/update"; then
    rm -f "$payload" "$response"
    cancel_generate_root
    return 1
  fi
  # The update is answered, but the attempt is only known to be gone once a token
  # was decoded: a threshold-above-one config would still hold it open, and the
  # failure paths below then cancel it.
  rm -f "$payload"
  response_one_line=$(tr '\n' ' ' < "$response")
  rm -f "$response"
  encoded=$(printf '%s' "$response_one_line" | sed -n 's/.*"encoded_root_token"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
  if [ -z "$encoded" ]; then
    echo "Vault bootstrap warning: generate-root completed without a decodable token; a root token may be live" >&2
    cancel_generate_root
    return 1
  fi
  if ! root_token=$(vault operator generate-root -decode="$encoded" -otp="$otp"); then
    root_token=
    cancel_generate_root
    return 1
  fi
  if [ -z "$root_token" ]; then
    root_token=
    cancel_generate_root
    return 1
  fi
  # A completed update dropped the attempt server-side; the parent shell owns the
  # credential from here, so a signal arriving during the next command still
  # reaches the revoke trap.
  generate_root_pending=0
  admin_token_generated=1
  return 0
}

# Set `root_token` (and `admin_token_generated`, which drives the exit trap) to
# a usable administrative token: the first-boot root token, an operator-supplied
# seed that is actually a valid token (prod), or a freshly minted generate-root
# token. The latter is what repairs a dev Vault: the overlay seeds a throwaway
# random value that was never a Vault token. Assigns globals, so it must not be
# called in a subshell.
resolve_admin_token() {
  admin_token_generated=0
  if [ -n "${root_token:-}" ] && VAULT_TOKEN="$root_token" vault token lookup >/dev/null 2>&1; then
    return 0
  fi
  root_token=
  generate_root_token
}

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
# `vault status` exits 2 for BOTH a never-initialized Vault and an
# initialized-but-sealed one (Vault 1.20). Only operator-init when the report
# says `Initialized false`; a sealed restart must fall through to the unseal
# path below, otherwise it would abort with "Vault is already initialized"
# (found via the issue #468 dev overlay restart path).
if [ "$status" -eq 2 ] && vault status 2>/dev/null | grep -q '^Initialized[[:space:]]*false'; then
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
  chown 1000:1000 "$unseal_file"
  root_token="$generated_root"
  initialized_now=1
fi

if ! vault status >/dev/null 2>&1; then
  if [ ! -s "$unseal_file" ]; then
    echo "Vault bootstrap failed: sealed Vault has no persisted unseal key" >&2
    exit 1
  fi
  # The Vault CLI only accepts an unseal key as an argument or interactively;
  # its non-interactive stdin mode fails without a TTY. Use the local HTTPS
  # API with a short-lived request file so the key never appears in argv.
  unseal_payload="$bootstrap_dir/.unseal-request.$$"
  umask 077
  printf '{"key":"%s"}\n' "$(cat "$unseal_file")" > "$unseal_payload"
  prepare_wget_ca
  if ! wget --quiet \
      --header='Content-Type: application/json' \
      --post-file="$unseal_payload" -O /dev/null \
      "$VAULT_ADDR/v1/sys/unseal"; then
    rm -f "$unseal_payload"
    echo "Vault bootstrap failed: unseal request failed" >&2
    exit 1
  fi
  rm -f "$unseal_payload"
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

# The generated root token (first boot), a still-valid operator-provided seed,
# or a `generate-root` token (lapsed app token — see `resolve_admin_token`) is
# used only for administrative bootstrap calls and revoked again below.
if ! resolve_admin_token; then
  echo "Vault bootstrap failed: no usable administrative token (bootstrap seed is not a valid token and generate-root failed)" >&2
  exit 1
fi
export VAULT_TOKEN="$root_token"
if ! vault token lookup >/dev/null 2>&1; then
  echo "Vault bootstrap failed: no usable administrative token" >&2
  exit 1
fi

# Housekeeping, in this order: revoke a token a previous run minted and never got
# to revoke, then record this run's own accessor before any command can fail.
revoke_stale_admin_token
record_admin_accessor

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
path "transit/keys/photo-sse-c" {
  # `update` alongside `create` is required by the Transit key-creation
  # endpoint: the app's `ensure_key` POST creates the bucket key on first use.
  capabilities = ["create", "read", "update"]
}
path "transit/datakey/plaintext/photo-sse-c" {
  capabilities = ["update"]
}
path "transit/decrypt/photo-sse-c" {
  capabilities = ["update"]
}
path "kv/data/photo-sse-c" {
  capabilities = ["create", "read", "update"]
}
path "kv/data/photo-sse-c-rotation/*" {
  capabilities = ["create", "read", "update"]
}
# Rotation metadata deletion is intentionally excluded from the app token.
# An operator creates a short-lived, per-rotation cleanup token for the exact
# candidate and rollback metadata paths after the rollback window.
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
# surviving credential is the least-privilege app token in its own volume, so a
# failed revoke fails the run — the flag stays set and the EXIT trap retries it
# once more rather than exiting 0 with a live minted root token. A supplied token
# keeps the historical best-effort behavior: it is the operator's credential.
if [ "$admin_token_generated" = "1" ]; then
  if ! VAULT_TOKEN="$root_token" vault token revoke -self >/dev/null 2>&1; then
    echo "Vault bootstrap failed: could not revoke the minted administrative token" >&2
    exit 1
  fi
  rm -f "$admin_accessor_file"
  admin_token_generated=0
else
  VAULT_TOKEN="$root_token" vault token revoke -self >/dev/null 2>&1 || true
fi
unset VAULT_TOKEN VAULT_BOOTSTRAP_TOKEN VAULT_BOOTSTRAP_TOKEN_FILE root_token generated_root unseal_key init_json init_one_line app_token token_json nonce otp encoded response_one_line payload response wget_ca_prepared accessor stale_accessor cancel_try

echo "Vault bootstrap complete (Transit, KV-v2, and app policy ready)"
