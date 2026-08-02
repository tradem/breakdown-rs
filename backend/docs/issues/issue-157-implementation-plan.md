# Issue #157 – Implementierungsplan

## Ziel

External credentials are accepted only at the API edge, encrypted with a
per-credential Vault Transit DEK, and persisted in Vault KV-v2. The event store,
Postgres projection, audit rows, OpenAPI responses, and logs contain only the
opaque Vault reference and binding metadata.

## Abgrenzung zu Issue #159

Issue #159 explicitly owns Garage SSE-C/photo-storage changes. This change
therefore does **not** modify `PhotoStorage`, Garage object headers, photo
migrations, or photo endpoints. It provides the Vault service/bootstrap and the
generic credential API that #159 can consume later.

Settings routes remain authenticated-only at middleware level and add a
handler-internal `AUTHZ-GATE` that permits only active
`CostumeDesigner`/`CostumeAssistant` memberships. Credential bytes never enter
a command or event; broader settings capability modelling remains an ADR-028
follow-up.

## Work packages

- [x] **Vault runtime** – add a digest-pinned file-storage Vault service, encrypted-volume documentation, health gating, and an idempotent first-boot bootstrap. Enable Transit and KV-v2, create the least-privilege app policy/token, and never mount the bootstrap/root token into the API.
- [x] **Vault adapter** – add an async, redacting Vault HTTP client. Implement per-credential Transit datakey creation, AES-256-GCM encryption in memory, KV-v2 storage/fetch, and key destruction. Vault outages are represented as an unavailable dependency rather than an API boot failure.
- [x] **Settings domain** – add the Settings aggregate, reference-only commands/events, state, view and ports. Add tests proving serialization/event payloads contain no submitted secret.
- [x] **Persistence** – add the reference-only `projection_settings` table, idempotent projector, repository, event-store command adapter, and projector/audit registration.
- [x] **API** – add authenticated settings credential submit/read/revoke routes. Submit stores the secret in Vault before dispatching a reference-only command; responses never echo it. Map Vault unavailability to `503`.
- [x] **Boot wiring** – make Vault optional at process boot, wire the client and settings ports, and keep existing photo/reporting boot unchanged.
- [x] **Verification/docs** – add compose/bootstrap tests, core tests, redaction tests, OpenAPI schemas, runbook notes, `docker compose config` validation, formatting, clippy and focused test runs.

## Verification completed

- `cargo test --workspace --exclude integration-tests` (335 passed, 1 ignored)
- `cargo test -p integration-tests --no-run`
- `cargo test -p architecture_tests`
- `cargo clippy --workspace --all-targets -- -D warnings`
- `cargo deny check bans`
- `docker compose ... config`, shell syntax, diff whitespace checks
- Live Vault smoke: first bootstrap, app-policy datakey access, crypto-shredding
  key deletion, and idempotent restart/app-token renewal

The repository-wide historical gitleaks scan still reports two pre-existing
Garage test fixture literals in `crates/integration-tests/tests/fixtures.rs`;
all files introduced by this change (including the bootstrap script) scan clean.

## Explicit assumptions

1. The first release exposes a generic provider string (for example `gdrive` or
   `ai`) rather than implementing a provider-specific sync client. Those clients
   can consume the reference through the Vault port in follow-up changes.
2. The bootstrap seed is supplied only to the one-shot bootstrap container;
   the API reads the generated short-lived app token from the encrypted Vault
   volume. The Vault service itself receives no administrative token. The first
   Vault init generates a root token in-memory (Vault 1.20 removed the
   caller-supplied root-token flag), revokes it after provisioning, and keeps
   only the unseal key plus orphaned app token on their dedicated volumes.
3. Vault uses the existing step-ca mesh for native internal TLS. The API and
   bootstrap client pin the step-ca root; the unseal key and app token remain in
   separate persistent volumes with separate backup/custody rules.
4. Destruction is a per-credential Transit-key operation. Shared-key
   reference-counting is intentionally not introduced because #157 creates one
   key per binding.
