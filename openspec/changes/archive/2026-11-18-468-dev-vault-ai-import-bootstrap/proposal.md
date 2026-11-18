<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4-flash (neuralwatt) -->

# Dev Vault overlay + credential-role bootstrap for host-run AI import (issue #468)

> Dev-infra change (no wire contract or spec deltas): a dev Vault overlay,
> a dev credential-role bootstrap, and a full-stack `enable-dev-ai-import.sh`
> so a host-run dev API can exercise AI import end-to-end with a real provider
> key stored through the settings flow.

## Why

Against the local dev runtime (`docker-compose.dev.yml` + host-run
`cargo run -p api` in dev-auth mode) the provider-API-key / AI-import flow is
untestable: there is no Vault service (ADR-027 is prod-only), so the
`/settings` credential and AI-config `vault_key_id` flows 503; the dev user
holds no active credential role after a DB reset, so the AUTHZ-GATED
`/ai-import/*` + `/settings/*` handlers 403; and `enable-dev-ai-import.sh`
(issue #428) only provisions Garage payload storage, not the Vault the
credential flow requires.

## What Changes

- **Vault overlay** — new `docker-compose.dev.vault.yml` (+ `vault/config.dev.hcl`,
  plaintext `tls_disable`) plus a host driver `scripts/enable-dev-vault.sh`:
  boots a digest-pinned `hashicorp/vault:1.20.4` service on loopback
  `127.0.0.1:8200`, runs the existing `vault-bootstrap` one-shot (parameterized
  so TLS is opt-in), and writes `.env.dev-vault.local` with
  `VAULT_ADDR=http://127.0.0.1:8200` + `VAULT_APP_TOKEN_FILE=...` for the
  host-run API. Idempotent (renews the 24 h app token on re-run).
- **Credential-role bootstrap** — new `scripts/bootstrap-dev-credential-role.sh`:
  after the API is up, POSTs `series → season → block` on behalf of `DEV_AUTH_SUB`,
  which makes the dev user an active `CostumeAssistant` via the existing
  `BootstrapOwner` command — the genuine ADR-018/ADR-028 membership path (no
  production authz code change; the credential gates keep enforcing).
- **Full-stack one command** — `scripts/enable-dev-ai-import.sh` now also boots
  the Vault overlay, merges the Vault env, and with `--run` waits for the API
  then runs the credential-role bootstrap before foregrounding it.
- **`vault-bootstrap.sh`** — TLS becomes opt-in (`VAULT_CACERT` honoured when
  set, prod compose unchanged); the plaintext dev overlay leaves it unset.
  Grants `update` on `transit/keys/photo-sse-c` (Vault key-creation requires
  create+update) and runs `operator init` only when `vault status` reports
  `Initialized false` — exit code 2 covers both uninitialized and sealed, so a
  sealed restart used to abort with "Vault is already initialized" (prod + dev).
- **Docs** — `local-dev-runtime.instructions.md`: dev Vault overlay,
  credential-role bootstrap, full-stack AI import, `VAULT_*` env vars, reset.

## Impact

- No backend crate version bump (`core`/`infra`/`api` unchanged).
- No OpenAPI drift; no new problem codes.
- Security posture unchanged: loopback-only plaintext Vault + Garage ports are
  explicit dev overlays (ADR-024 `REQUIRE_IN_TRANSIT_TLS` untouched);
  dev-derived secrets are never valid outside the local stack.
- New git-ignored state directory `backend/.vault-dev/` (app token, unseal key,
  dev bootstrap token).
