<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

# Design — project-scoped membership

## D1 — A second scope, not a widened block scope

Block membership stays exactly as specified today ("Roles are block-scoped
domain values", including role rotation at block boundaries). The project scope
is a **separate aggregate** (`project_membership-{project_id}-{user_id}`) with
its own events, projection and query.

Rejected alternative: `projection_membership.block_id` nullable plus a
`project_id` column. It reuses one row shape for two lifecycles, makes every
existing query's `JOIN projection_block` silently wrong, and would have to
re-litigate the block-scoped requirement instead of extending it.

## D2 — Effective role resolution is one function

`effective_costume_role_in_season(season, user)`:

1. block-scoped role in any block of `season` (existing query, unchanged),
2. else project-scoped role whose `project_id` is `season.project_id`,
3. else deny.

Fail-closed: a projection miss or a repository error is `Deny`, never `Allow`
(mirrors `MembershipAuthorizationPolicy::authorize`).

This is the only place the precedence lives — no handler re-implements it.

## D3 — Bootstrap on season creation

`829`/`827` need "the caller created the production, so they are a costume
person". The existing precedent is block creation bootstrapping its owner
(`OwnerBootstrapped`), so the project equivalent is **season creation**
bootstrapping the creator's project-scoped `costume_designer`. Idempotent, so a
projector replay or a second season in the same project is a no-op.

Rationale for `costume_designer`: it is the strongest of the three costume
roles and the one a production creator holds; assistants/supervisors are
granted explicitly afterwards.

## D4 — Read model and query shape

`projection_project_membership(project_id, user_id, role, state, joined_at,
updated_at, projector_version)`, PK `(project_id, user_id)`, partial index on
`(project_id, state, role)` for the authorization query. The projection keeps
`state` (`active`/… ) so a revocation is a state transition, not a row delete —
the same shape `projection_membership` uses.

## D5 — Migration and existing data

No backfill: existing block-scoped memberships keep working through step 1 of
D2. Orphaned `projection_membership` rows (block no longer exists) stay inert;
they are a dev-data artifact, not a code path. A production upgrade needs no
action, because every caller that works today holds a block role.

## D6 — What is deliberately not done here

- No `Project` aggregate (the opaque `ProjectId` seam stays; ADR-035 S1).
- No new `*_in_season` authorization predicate (ADR-035 B2). The existing
  season predicate keeps its name and level; only its *resolution* widens.
- No client change: the Flutter client already declares the season and renders
  whatever code the server returns.
- Project-scoped grants are **not** implicitly inherited by new seasons' blocks;
  they are a project-level statement, resolved at check time.

## Risks

- **Privilege widening.** A project role now satisfies every season-scoped
  check in that project. Mitigation: only the three costume roles are accepted
  (never `ops_admin`, never a report-archive role), the same allowlist the
  block-scoped predicate uses; the report-archive predicate keeps its narrower
  two-role list and does **not** gain the project fallback.
- **Bootstrap ambiguity.** Deferred to the proposal's open question; if the
  answer differs, only D3 changes.
