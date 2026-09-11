<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: omen-alpha (opencode-go) -->

# Proposal: Authenticated projector-health HTTP endpoint (issue #409)

## Why

Issue #37 shipped the durable projector dead-letter (`projection_dead_letter`)
and the programmatic health signal (`infra::projectors::ProjectorHealthRepository`,
runbook SQL). The operator-facing **HTTP endpoint** was deliberately deferred
because it needs an authorization decision. This change implements
`GET /v1/ops/projector-health` and resolves that decision.

## Authorization Decision (the issue's core ask)

**Decision: new ops capability in the membership model — additive `Role::OpsAdmin`**

- The membership `Role` enum is documented as *open for additive extension*;
  adding `Role::OpsAdmin` (token `ops_admin`) is a non-breaking, replay-safe
  change (role column is text; no migration).
- New port predicate `MembershipRepository::has_active_ops_role(user_id)`:
  active membership with role `ops_admin` in **any** block (deployment-wide
  read, block rows are just where the role lives).
- New fallible policy method `AuthorizationPolicy::authorize_ops(&UserId)`
  (default `Deny`), mirroring `authorize_credential_role` (ADR-027 pattern).
- **Grant path / escalation guard:** `Role::OpsAdmin` may only be granted by a
  caller who already holds ops access — `invite_member` and `grant_role` gain
  an API-edge pre-check (403 `domain.forbidden`, `// AUTHZ-GATE:`). Block-scoped
  costume roles can never self-escalate into ops.
- **Cold start (bootstrap):** the deployment operator lists trusted OIDC subs
  in `OPS_ADMIN_SUBS` (comma-separated env var, default empty). The
  `MembershipAuthorizationPolicy` is constructed with this allowlist;
  `authorize_ops` = `has_active_ops_role(user) OR allowlist.contains(sub)`.
  The operator bootstraps themselves via env, delegates through the normal
  membership API, then removes the env var. Standard config-seeded bootstrap
  (Grafana `ADMIN_USER` pattern); no direct projection/event-store seeding.

## What Changes

- **core** (0.11.0 → 0.12.0, MINOR):
  - `membership`: `Role::OpsAdmin` variant + `"ops_admin"` token (pinned by
    the existing token-representation test).
  - `membership/ports.rs`: `MembershipRepository::has_active_ops_role`.
  - `membership/policy.rs`: `AuthorizationPolicy::authorize_ops` (fallible,
    default Deny).
  - New `ops` module: `DeadLetterEntry`, `CheckpointProgress`,
    `ProjectorHealthSnapshot` DTOs (utoipa `ToSchema`) + port trait
    `ProjectorHealthRepository` (`list_dead_letters`, `dead_letter_count`,
    `checkpoint_progress`). DTOs move from infra (infra re-exports for
    compat); core gains **no** sqlx dependency.
- **infra** (0.16.0 → 0.17.0, MINOR):
  - `queries/membership.rs`: implement `has_active_ops_role` (static SQL).
  - `projectors/health.rs`: implement the core port trait on
    `ProjectorHealthRepository` (manual row mapping — `sqlx::FromRow` stays
    infra-side); re-export moved DTOs.
- **api** (0.10.0 → 0.11.0, MINOR):
  - `Ports` gains `type ProjectorHealthRepo` + accessor (test fakes updated).
  - `MembershipAuthorizationPolicy` gains the ops allowlist (injected at
    state construction); `authorize_ops` implemented.
  - New handler `get_projector_health` (`GET /v1/ops/projector-health`,
    `limit` query param, default 100 / capped 500) with handler-internal
    `// AUTHZ-GATE:` via `authorize_ops` → 403 on denial.
  - Escalation guard in `invite_member` / `grant_role` for `ops_admin`.
  - `requirement_for`: `/ops` → `Requirement::Authenticated` (explicit match).
  - Route registered, utoipa schemas registered, `openapi.yaml` regenerated.
- **docs:** runbook section gains the HTTP endpoint (issue #37 SQL stays);
  `docs/security/security-architecture.md` records the ops capability
  decision (issue #85 sync rule).

## Problem Codes (ADR-031)

No new codes: failures map to existing `domain.forbidden` (403),
`http.bad-query-param` (400), `domain.service-unavailable` (503),
`http.internal-error` (500) via the existing registry + problem builder.

## Risks / Trade-offs

- `Role::OpsAdmin` lives on block-scoped membership rows but is checked
  deployment-wide — documented; a future dedicated ops-principal model can
  migrate the predicate without touching the gate call sites.
- The `OPS_ADMIN_SUBS` allowlist is checked at request time (membership OR
  config) — removing a sub from env revokes bootstrap access immediately.
- `Ports` trait change touches all test fakes (mechanical, compiler-driven).
