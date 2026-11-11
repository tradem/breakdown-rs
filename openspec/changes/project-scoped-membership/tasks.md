<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

# Tasks — project-scoped membership

## 1. Domain (`crates/core`)

- [x] 1.1 `project_membership` module: aggregate (`project_id`, `user_id`,
      `role`, `state`), commands `BootstrapProjectOwner` / `GrantProjectRole` /
      `RevokeProjectRole`, events `ProjectOwnerBootstrapped` /
      `ProjectRoleGranted` / `ProjectRoleRevoked`.
- [x] 1.2 Reuse the existing `Role` enum; the grant accepts only
      `costume_designer` / `wardrobe_supervisor` / `costume_assistant`
      (validate in the aggregate, not only in the handler).
- [x] 1.3 Unit tests: idempotent bootstrap, grant on an already-granted role is
      a no-op, revoke of an absent grant is a no-op, non-costume role is
      rejected.

## 2. Infrastructure (`crates/infra`)

- [x] 2.1 Migration: `projection_project_membership` (PK
      `(project_id, user_id)`, partial index
      `(project_id, state, role) WHERE state = 'active'`) + projector
      checkpoint row.
- [x] 2.2 `ProjectMembershipProjector` (idempotent, version-guarded
      `WHERE version < $N`), registered in `main.rs`.
- [x] 2.3 `MembershipRepository::effective_costume_role_in_season`:
      block scope first, then project scope, fail-closed.
- [x] 2.4 Bootstrap call in the season command adapter (projector-independent:
      the command path emits it, best-effort per the audit-metadata doctrine).
- [x] 2.5 Tests: projector idempotency, resolution precedence (block wins,
      project falls back), deny on projection miss.

## 3. API (`crates/api`)

- [x] 3.1 `authorize_season_result` resolves through
      `effective_costume_role_in_season`; doc comment states the precedence.
- [x] 3.2 `// AUTHZ-GATE:` comments unchanged in shape; verify the block-less
      AI-import upload (`829` D1) now allows a project role holder.
- [x] 3.3 `has_active_report_archive_role_in_season` deliberately keeps the
      block-only resolution (two-role list) — assert that in a test.
- [x] 3.4 Integration (tier 4): season with **no block** + project-scoped
      costume role → `POST /v1/ai-import/scripts` with `X-Declared-Season` is
      accepted (202) and the job has `block_id = NULL`.
- [x] 3.5 Integration: a caller with no role at all still gets
      `403 ai-import.forbidden` (no widening).

## 4. Docs and gates

- [x] 4.1 `backend/AGENTS.md` §1 cross-aggregate/authorization note: record the
      second scope level and the precedence.
- [x] 4.2 `docs/security/security-architecture.md`: authorization matrix row
      for project-scoped roles.
- [x] 4.3 New problem codes if the grant command surfaces validation
      (`project-membership.*`) — via `problem_codes!` only (job
      `problem-code-registry`).
      *Not needed:* the grant command has no HTTP surface yet — it is dispatched
      from the season command adapter (`BootstrapProjectOwner`) and, for explicit
      grants, only from Rust callers. The aggregate's `NonCostumeRole` rejection
      therefore never reaches a client, so no code is registered. Add
      `project-membership.*` codes together with the future grant route.
- [ ] 4.4 Test-only dev affordance: a documented way to grant a project role on
      an existing dev dataset (script or `reset-dev-data` extension) so the
      live workflow can be re-verified without hand-written SQL.
      *Partially satisfied:* a NEW season bootstraps its creator automatically
      (`SeasonCommandsImpl::create`), so the documented live path needs no SQL at
      all. Only a dataset whose seasons predate this change still needs a manual
      grant (one `ProjectMembership::execute` with `BootstrapProjectOwner`, or
      `reset-dev-data`).

## 5. Verification

- [ ] 5.1 Live check: season with no blocks + `dev-user` project role →
      upload accepted → block derived from the script (`827`/`829`).
- [ ] 5.2 `cargo test -p architecture_tests`, `cargo deny check bans`,
      OpenAPI drift test (no contract change expected).
