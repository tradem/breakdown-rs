<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3 (neuralwatt) -->

# 552 — AI config rejects a vault_key_id the caller does not own (confused deputy)

## Why

An AI-config `vault_key_id` is accepted from the client without any check that the
named credential binding belongs to the caller. The AI import worker later derives
the Vault owner from the key string itself (`settings_id_from_binding_key`), so a
credential-role member who supplies another user's live binding key makes their own
AI jobs read and use that foreign credential (confused deputy / quota + billing
abuse). The ownership relationship is not modelled in the read model, so an
API-edge comparison was previously impossible.

## What Changes

1. **Read model:** `projection_settings` gains an `owner TEXT` column (nullable —
   legacy rows), populated by the settings projector from `EventMetadata.actor`
   (already persisted with every settings event; no event-schema change).
   `CredentialBound` sets it; `CredentialRotated` never mutates it (rotation
   backfill would let any credential-role member claim a legacy binding —
   settings rotate/revoke handlers do not verify the rotating actor), indexed.
2. **API edge (only legitimate read-model consumer — CQRS boundary):**
   - `create_ai_config` resolves the binding and requires `owner == caller`;
     unknown or foreign keys surface `403 ai-config.vault-key-forbidden`.
   - `update_ai_config` (introduced key only): the replacement pre-check now
     resolves ownership first (same 403 code), then keeps the #528
     active-provider check (`ai-config.provider-mismatch` 409 unchanged).
   - **Fail closed (user decision):** legacy bindings with `owner IS NULL` are
     denied until re-projection (runbook §10; recovery is re-projection only).
3. **Worker posture (documentation):** the worker continues to trust the stored
   `config.vault_key_id` — every stored value is now edge-vetted at create/update
   time. The fail-closed shape validation in `AiCredentialResolver` stays.
4. **Tests:** wire tests reject a foreign-but-valid binding on create and update
   (unknown keys fail closed into the same 403 — no key-existence oracle);
   integration contract test asserts the projector populates the owner from
   event metadata and that rotation never mutates it (legacy NULL stays NULL).

## Impact

- **core** `0.13.0 → 0.14.0` (MINOR): `SettingsView` gains public `owner` field.
- **infra** `0.18.0 → 0.19.0` (MINOR): settings projector/repository carry owner.
- **api** `0.12.0 → 0.12.1` (PATCH): handler-internal pre-check only, no new
  public API; wire contract gains the `owner` view field + new problem code.
- New problem code `ai-config.vault-key-forbidden` (403) in the `problem_codes!`
  registry with Fluent texts (en/de).
- `docs/security/security-architecture.md` documents the worker posture.
- Upgrade note: legacy `projection_settings` rows deny until re-projected —
  runbook gets a re-projection step; dev resets volumes.
