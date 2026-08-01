# ADR-028: Access Control for the Costume Designer / Costume Assistant Settings Aggregates View

**Status**: Proposed
**Date**: 2026-08-01
**Author**: Tobias Rademacher (@tradem); glm-5.2 (neuralwatt)
**Related**: ADR-010 (OIDC), ADR-018 (JWT validation + dev-auth toggle),
ADR-027 (secrets vault & reference pattern), AGENTS §3 (handler-internal authz)

---

## Context

"Settings Aggregates" hold the external-credential **references** owned by the
costume department's privileged roles: the **Costume Designer**
(`Role::CostumeDesigner`, serde `costume_designer`; German `Kostümbildner*in`)
and the **Costume Assistant** (`Role::CostumeAssistant`, serde
`costume_assistant`; German `Kostümassistent*in`). Both roles may save external
credentials (GDrive access data, future AI-backend tokens) per ADR-027. Per
ADR-027 these aggregates carry only non-sensitive `vault_key_id` references,
not secret material — but the references and their lifecycle (create/rotate/
revoke) are themselves sensitive administration surface: a user who can *create*
or *repoint* a credential binding can steer external integrations, and a user
who can *read* the binding list can enumerate our integration footprint.

The existing authorization model (ADR-010/018, AGENTS §3) is membership-based:
OIDC identity → `CurrentUser` → `AuthorizationPolicy` checks (e.g.
`has_active_costume_role_in_season`) for season-scoped access. Photo handlers
use `// AUTHZ-GATE:` handler-internal gates because they are only
`Requirement::Authenticated` at the middleware layer (AGENTS §3).

We need to decide who can see and mutate the Settings Aggregates view in the
admin panel, and how that decision is enforced.

## Decision

Make **Settings Aggregates access a distinct, narrowly-scoped authorization
capability**, enforced with the same handler-internal `// AUTHZ-GATE:` pattern
used by the photo handlers, layered on the existing membership/OIDC model:

1. **Capability, not just role name.** Introduce a dedicated authorization
   capability — e.g. `settings:manage_external_credentials` — granted to the
   **Costume Designer** and **Costume Assistant** memberships in a
   production-scoped Settings context
   (production-wide, not per-season, because external credentials are
   integration-level, not per-show). A new `AuthorizationPolicy` method
   `can_manage_external_credentials(&self, user: &CurrentUser) -> bool` is the
   single decision point; all settings handlers call it.
2. **`// AUTHZ-GATE:` on every settings handler.** Because credentials are
   integration-level and not season-scoped, these routes are not protectable
   by season-scoped membership middleware; each handler is
   `Requirement::Authenticated` at the middleware layer and performs the
   in-handler `can_manage_external_credentials` check, returning `403` on
   denial — exactly the documented pattern for `Authenticated`-only routes
   (AGENTS §3). Aiding review, every gate carries a `// AUTHZ-GATE:` comment.
3. **Audit.** Every read/mutation of a Settings Aggregate writes an
   `projection_audit` row (the INSERT-only audit table from the main-runtime
   boot sequence) recording actor `sub`, action, `settings_aggregate_id`, and
   the `vault_key_id` reference touched — never the secret.
4. **Reference-only transport.** The settings panel never receives plaintext
   secrets back; submit endpoints accept the raw credential (forwarded to the
   vault, ADR-027) and immediately discard it, returning only the
   `vault_key_id`. Read endpoints return only binding metadata, never a secret
   payload field — consistent with the OpenAPI/schema rule in ADR-027.
5. **Dev mode.** `AUTHZ_ENFORCE=false` (dev-auth mode, ADR-018) keeps the
   gate non-blocking for local dev/tests; production enforces (`AUTHZ_ENFORCE`
   unset or truthy). This mirrors the OIDC dev-auth convention.

## Consequences

### Positive
- One decision point (`can_manage_external_credentials`) is easy to audit and
  to grep for via `// AUTHZ-GATE:`.
- Reuses the existing membership/audit plumbing — no new auth framework.
- Settings panel surface is minimal and reference-only; even a fully
  authorised admin cannot exfiltrate raw secrets through it (the API simply
  does not return them).

### Negative
- A new capability to provision: membership seed data must grant
  `settings:manage_external_credentials` to the right Costume Designers and
  Costume Assistants, and
  this must be part of the onboarding runbook.
- Production-wide scope (not per-season) is a deliberate simplifying
  assumption; if a production demands multi-org isolation later, the capability
  must be re-scoped per organisation.
- The dev-auth non-enforcement can mask a missing gate in CI; mitigate with a
  mechanical check that files under the settings routes directory contain a
  `// AUTHZ-GATE:` comment (analogous to the `cqrs-boundary` ast-grep rule,
  AGENTS §4).

## Alternatives Considered

1. **Season-scoped membership reuse** — rejected: external credentials are
   integration-level, not per-show; forcing them into season scope would either
   over-grant (any season admin gets all credentials) or under-grant.
2. **OIDC role/claim-based authorization (claims like `role: settings-admin`)** —
   viable and reduces DB membership lookups, but couples our authz to the IdP's
   claim model and complicates dev-auth/testing; we keep IdP-agnostic
   membership (ADR-010) and treat claims as identity input only.
3. **Dedicated RBAC framework / framework-injected policy** — rejected on the
   "Poor Man's DI, no DI frameworks" principle (AGENTS §1); the handler-internal
   gate matches the established photo-handler pattern.

## Security / Compliance Notes
- `AUTHZ_ENFORCE` must be enforced (unset/truthy) in production; startup
  config check fails fast if dev-auth mode is detected alongside a production
  `OIDC_ISS`.
- Audit rows for settings access must scrub any echoed secret material — they
  store `vault_key_id` only.
- Combine with ADR-027's log-redacting layer so the settings handler's tracing
  spans never surface the submitted credential in plaintext during the brief
  window the API holds it for vault submission.
