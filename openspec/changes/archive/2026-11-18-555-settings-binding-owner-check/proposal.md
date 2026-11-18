<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: space-bunny-free (opencode-go) -->

# 555 — settings credential rotate/revoke (and read) verify the binding owner

## Why

`PATCH /settings/{id}/gdrive` and `DELETE /settings/{id}` gate on the
credential role only (`has_active_credential_role`, ADR-028) and never compare
the caller with the binding's recorded owner. Any active credential-role member
can therefore rotate another user's binding — which replaces the Vault secret
and destroys the superseded one — or revoke it outright, destroying the foreign
secret. `GET /settings/{id}` has the same gap on the read side: it discloses a
foreign `vault_key_id` and binding state to every credential-role member.

Issue #552 introduced per-binding ownership (`projection_settings.owner`,
populated from `EventMetadata.actor`) for the AI-config vault-key pre-check and
explicitly left the settings rotate/revoke gap open as follow-up #555 (a
rotation `COALESCE` backfill was removed precisely because the rotating actor
was never checked).

## What Changes

1. **API edge (only legitimate read-model consumer — CQRS boundary):**
   `get_settings`, `rotate_gdrive_credential` and `revoke_settings` require
   `projection_settings.owner == caller` in addition to the credential role; a
   foreign binding surfaces **403 `settings.binding-forbidden`**. The pre-check
   runs *before* any Vault write and *before* the command dispatch, so a
   non-owner can neither replace/destroy nor revoke another user's secret, and
   the aggregate is never asked to revoke a foreign binding.
2. **Fail closed (same posture as #552):** a legacy row with `owner IS NULL`
   denies into the identical 403 — otherwise rotate would be the way to claim
   such a binding. Runbook §10 documents the affected surfaces.
3. **Scoped problem code (ADR-031):** new registry entry
   `settings.binding-forbidden` (403) in the `problem_codes!` macro with Fluent
   texts (en/de) and a golden snapshot. It is deliberately distinct from the
   credential-role denial `settings.forbidden`, so the client can render
   "this credential is not yours" instead of a generic authorization failure.
4. **Tests:** wire tests cover the foreign-owner denial and the legacy
   NULL-owner denial on all three handlers, plus the owner-allowed paths; the
   foreign rotate/revoke assertions prove the command was never dispatched.
5. **Docs:** threat model (`docs/security/security-architecture.md`) gains the
   settings owner gate in the ownership section and in the middleware
   allowlist-exception table; the settings `// AUTHZ-GATE:` comments name the
   ownership pre-check; runbook §10 is corrected (its #552 rationale stated
   that the settings handlers do not verify the actor — no longer true).
6. **Accepted trade-off:** a foreign binding answers `403` where an unknown id
   answers `404`. The id is a client-held UUIDv7 and the rotate path already
   split `404` (unknown) from `409` (revoked / wrong provider), so the extra
   bit is accepted in exchange for a stable, client-branchable denial code.

## Impact

- **core** `0.14.0 → 0.15.0` (MINOR): new public problem-code constant.
- **api** `0.12.1 → 0.13.0` (MINOR): new public `ApiError::SettingsBindingForbidden`
  variant, handler-internal pre-check, re-pinned `breakdown_core` 0.15.0.
- **infra** `0.19.0` (none): the owner column, projector and repository already
  carry ownership from #552 — no read-model change here.
- Wire contract: `openapi.yaml` gains the `403` responses on the three settings
  routes and the registry entry. The generated Dart client is byte-identical
  (verified by regenerating from the pre- and post-change spec), so no
  `breakdown_api` churn.
- Upgrade note: legacy `projection_settings` rows deny on the settings handlers
  too until re-projected (runbook §10, unchanged procedure).
