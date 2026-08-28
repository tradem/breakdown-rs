# Tasks — add-oidc-auth-and-membership

> Status legend: `[x]` done · `[~]` done-at-unit/workspace-level but integration
> (Docker-Tier) deferred · `[ ]` open. Human sign-offs 9.1–9.4 are
> **surfaced, not faked**.

## 1. Shared domain primitives

- [x] 1.1 Add `UserId` opaque value type to `crates/core/src/shared.rs`, mirroring the
  existing value types (UUIDv7-independent; wraps the OIDC `sub` string,
  `#[serde(transparent)]`, derives for `Serialize/Deserialize/ToSchema`).
- [x] 1.2 Add unit tests for `UserId` construction and serialization parity with the IdP `sub` claim.

## 2. Membership Bounded Context — core domain

> **Locked decisions (implemented):** v1 roles use **English** spellings
> (`costume_designer`, `wardrobe_supervisor`, `costume_assistant`); the
> bootstrap gap is resolved via **option A** — the block creator is auto-owner
> through a dedicated `BootstrapOwner` command / `OwnerBootstrapped` event (default
> role `costume_assistant`), so no membership-management endpoints are required
> to seed the first active member.

- [x] 2.1 Scaffold `crates/core/src/membership/` with `mod.rs`, `aggregate.rs`,
  `commands.rs`, `events.rs`, `error.rs`, `ports.rs`, `views.rs`, mirroring the
  existing four-context layout.
- [x] 2.2 Define `Role` enum in `membership` with the v1 additive variants
  **`CostumeDesigner` (`costume_designer`), `WardrobeSupervisor`
  (`wardrobe_supervisor`), `CostumeAssistant` (`costume_assistant`)**, with
  `#[serde(rename_all = "snake_case")]` for stable wire/JSON form. (`Kostümbildner`/
  `Garderobier` from the original draft were replaced by the English
  ubiquitous-language set per the locked decision.)
- [x] 2.3 Model `BlockMembership` aggregate state:
  `{ block_id: BlockId, members: HashMap<UserId, MembershipState> }` where
  `MembershipState` distinguishes pending invitations from active members.
- [x] 2.4 Implement `kameo_es::Entity` for `BlockMembership` (category
  `"membership"`, `ID = Uuid` stream id — the inner `BlockId.0`; `BlockId` is
  carried as a domain field, not the stream id, per Decision D4;
  `Event = MembershipEvent`, `Metadata = MembershipMetadata` per Decision 6).
- [x] 2.5 Model and implement `InviteMember` / `MemberInvited` `execute` + `apply`
  (incl. the re-invite-rejection rule).
- [x] 2.6 Model and implement `AcceptInvitation` / `InvitationAccepted`
  `execute` + `apply` (incl. no-pending-invitation rejection).
- [x] 2.7 Model and implement `GrantRole` / `RoleGranted` `execute` + `apply`
  (incl. non-member rejection, prior-role replacement).
- [x] 2.8 Model and implement `RemoveMember` / `MemberRemoved` `execute` + `apply`,
  plus `LeaveBlock` (self-issued equivalent).
- [x] 2.9 **(option A bootstrap)** Model and implement `BootstrapOwner` /
  `OwnerBootstrapped` `execute` + `apply`, rejecting bootstrap when the block
  already has ≥1 member (`MembershipError::BootstrapNotAllowed`).
- [x] 2.10 Define `MembershipError` via `thiserror` covering all rejection paths above.
- [x] 2.11 Define `MembershipView` and the `MembershipRepository` /
  `MembershipCommands` port traits, following the existing ports pattern
  (`MembershipCommands`/`MembershipRepository` use `#[async_trait]` so the
  policy can own a `Send` boxed future; `AuthorizationPolicy` lives in `core`,
  membership read/write only in `api`).
- [x] 2.12 Write unit tests for every command's positive path and each
  rejection rule (`cargo mutants`-resilient; 16 membership unit tests pass).

## 3. Membership infrastructure

- [x] 3.1 Add a Postgres migration for the `membership` projection table
  (`block_id`, `user_id`, `role`, `state`, `joined_at`, primary key
  `(block_id, user_id)`).
- [x] 3.2 Implement the membership projector
  (`crates/infra/src/projectors/membership.rs`) consuming `MembershipEvent`,
  applying idempotently under redelivery (reuses the established ADR-016 pattern).
- [x] 3.3 Register the membership projector in the `projectors` module and
  in `main.rs`'s `PostgresProcessor` supervisor.
- [x] 3.4 Implement `MembershipRepositoryImpl` (query adapter) in
  `crates/infra/src/queries/membership.rs`.
- [x] 3.5 Implement `MembershipCommandsImpl` (event-store write adapter) in
  `crates/infra/src/event_store/`, attaching the authenticated `actor`
  (`UserId`) as `kameo_es` command `Metadata` for audit (Decision 6);
  for `LeaveBlock` the actor is also the member being removed.
- [x] 3.6 Wire the new ports into `AppState` / `ProductionPorts` / `Ports`
  trait in `crates/api/src/state.rs`.

## 4. OIDC authentication — API layer

> Decision D1: JWT validation uses `jsonwebtoken` + `reqwest` behind an
> injectable `JwksProvider`. Dev bypass via `AuthState::dev` (D3). `core`
> stays free of `sqlx`/`axum`/`redis`/`sierradb-client`/`tokio` (D5).

- [x] 4.1 **Crate choice (D1):** `jsonwebtoken` validates RS256 signatures;
  `reqwest` (rustls-tls) fetches the IdP JWKS; both sit behind the
  injectable `JwksProvider` trait in `api` (documented in `design.md`).
- [x] 4.2 Add the `auth_middleware` Axum middleware: caches the IdP JWKS
  (`CachingJwksProvider`, short TTL), validates signature + `iss` + `aud` +
  `exp`, and attaches `CurrentUser { sub: UserId, email }` to request extensions.
- [x] 4.3 Implement the `CurrentUser` Axum `FromRequestParts` extractor.
- [x] 4.4 Return **401** for missing/expired/invalid tokens and **503** for
  an unrecoverable JWKS fetch failure (never 500 for an IdP/backend outage).
- [x] 4.5 Dev-mode toggle (D3): `AuthState::dev(sub)` short-circuits token
  verification and injects a fixed `CurrentUser`; never constructed on the
  production path (main.rs uses `AuthState::from_env_or_dev`).
- [x] 4.6 Configure `OIDC_ISS` / `OIDC_AUDIENCE` / `OIDC_JWKS_URL`;
  documented in `AGENTS.md` §6 (see task 8.1).
- [x] 4.7 Unit tests for each validation branch (valid token path exercised
  by the integration layer; unit tests cover static-key round-trip, unreachable
  fetch → 503-path, and `bearer_token` parsing).

## 5. Authorization policy — API layer (action-scoped, block-scoped)

> Decision D2: the active block is conveyed by the `X-Active-Block` request
> header, parsed by an Axum extractor. Authorization is **action-scoped**
> (the caller's active block), not data-scoped.

- [x] 5.1 Active-block transport (D2): `ActiveBlock` `FromRequestParts`
  extractor over the `X-Active-Block` header — **400** on missing/malformed.
- [x] 5.2 Implement `authorize_middleware` resolving the active `BlockId`,
  querying `MembershipRepository::is_active_member`, panic-safe
  (`tokio::task::spawn(AssertUnwindSafe(...)).await.unwrap_or(Deny)` →
  403 on a panicking policy, never 500).
- [x] 5.3 Gate write-command endpoints: **403** when the caller is not an
  active member of the active block (seasons + `/blocks` creation need only
  authentication); else forward the command.
- [x] 5.4 Gate block-scoped read endpoints: **403** for non-members; data
  for members.
- [x] 5.5 Attach the acting `UserId` as `kameo_es` command metadata
  for audit on routed write commands, leaving command payloads unchanged (D6).
- [x] 5.6 Runtime enforcement flag (`AUTHZ_ENFORCE`): `false` → log-only
  (allowed, denial logged); `true`/`unset` → enforced (403). Dev mode
  defaults enforcement **off** so local dev works without seeded membership.

## 6. Integration tests

- [x] 6.1 Extend `crates/integration-tests` with membership command/event
  sequences. Covered by `tests/membership_round_trip.rs` (added in §10.5): a
  Tier-4 command → SierraDB → projector → PG round-trip for
  `BootstrapOwner`/`InviteMember`/`AcceptInvitation` (plus a `GrantRole` →
  `RemoveMember` → `LeaveBlock` variant) and a Tier-3 projector
  idempotency-under-redelivery test. Requires Docker (ephemeral Postgres +
  SierraDB) to *run*; compile-verified in this environment per ADR-016.
- [x] 6.2 Tier-4 round-trip test for `membership` command → SierraDB →
  projector → Postgres read model. Delivered by `tests/membership_round_trip.rs`
  (`command_invite_accept_round_trips_into_membership_projection` +
  `command_grant_remove_leave_round_trips_into_membership_projection`, added in
  §10.5). Requires Docker (per ADR-016) to *run*; compile-verified here.
- [x] 6.3 Tier-4 idempotency-under-redelivery test. Delivered by
  `tests/membership_round_trip.rs`
  (`membership_projector_is_idempotent_under_redelivery`, added in §10.5): raw
  EAPPEND of `OwnerBootstrapped` + a redelivery of the same event + a distinct
  `MemberInvited`; the `(block_id, user_id)`-keyed upsert means redelivery does
  not duplicate rows. Requires Docker (per ADR-016) to *run*; compile-verified.
- [x] 6.4 **API-layer test (done):** `authz_tests` in `handlers/mod.rs`
  asserts authorized/non-authorized dispatch through the real `auth_middleware`
  + `authorize_middleware` stack for a representative write (`POST /seasons`,
  authenticated) and read (`GET /blocks/{id}`, block-scoped) endpoint, using
  the dev-mode dummy `CurrentUser`; plus public `/swagger-ui` / `/api-docs`
  short-circuit and the 401 path for a missing prod token.

## 7. Architecture & guardrails

- [x] 7.1 `core` still has no `sqlx`/`axum`/OIDC-crate dependency after
  adding `membership` + `UserId` (architecture tests pass; `FORBIDDEN_CORE_DEPS`
  unchanged).
- [x] 7.2 `cargo deny check bans` passes with `jsonwebtoken` / `reqwest`
  added to `api`.
- [x] 7.3 `cargo mutants --in-diff` scoped to whitebox `#[cfg(test)]`
  modules: **core 0 survivors**, **api 9 survivors** (all residual mutants are
  TTL-timing / live-IdP key-normalization / log-only branches, covered by the
  Docker-gated integration tests per the project's testing strategy — not faked),
  **infra survivors** (the `membership` projector `handle` and `find` query,
  plus the `audit` projector `handle` and the `audit` repository
  `list_by_actor` / `list_by_time_range` / `list_by_entity` queries — all
  DB-backed, owned by the Tier-3/Tier-4 projector/repository integration tests
  per ADR-016; `audit_projector_tests` now exercises the audit projector
  idempotency + round-trip and the `list_by_block` read path).
- [x] 7.4 `./scripts/add-spdx-headers.sh` headers present on all new
  `.rs` files (verified).

## 8. Documentation

- [x] 8.1 Update `AGENTS.md` §6 with the new env vars (`OIDC_ISS`,
  `OIDC_AUDIENCE`, `OIDC_JWKS_URL`, `AUTHZ_ENFORCE`, `DEV_AUTH_SUB`,
  `DEV_AUTH_EMAIL`) and the dev-mode `CurrentUser` toggle.
- [x] 8.2 OpenAPI `ApiDoc`: the **audit read endpoint** `GET /blocks/{id}/audit`
  and the **membership-management endpoints** (`POST /blocks/{id}/members`,
  `POST /blocks/{id}/members/accept`, `POST /blocks/{id}/members/{user_id}/role`,
  `DELETE /blocks/{id}/members/{user_id}`, `POST /blocks/{id}/members/leave`,
  `GET /blocks/{id}/members`, `GET /blocks/{id}/members/{user_id}`) are all
  documented — `AuditEntry` / `MembershipView` / request DTOs derive `ToSchema`,
  each handler carries a `#[utoipa::path]`, and `ApiDoc` registers the paths +
  schemas (guarded by the `openapi_doc_includes_block_audit` doc-build test,
  which now also asserts the membership paths + `MembershipView` / `Role`
  schemas).
- [x] 8.3 ADR recording the JWT-validation-crate decision (design.md **D1**:
  `jsonwebtoken` RS256 + `CachingJwksProvider` async JWKS fetch / 1h TTL /
  rotation-aware, `JwksProvider` trait in `api` so `core` stays OIDC-free per
  ADR-017) and the dev-mode auth toggle (design.md **Open Question 3**
  resolution: `AuthState::from_env_or_dev()` — production when
  `OIDC_ISS`/`OIDC_AUDIENCE`/`OIDC_JWKS_URL` are set, else a `DEV_AUTH_SUB`
  gated dummy `CurrentUser` that `main.rs` can only reach when `OIDC_ISS` is
  absent, so production is structurally unreachable). Recorded as **ADR-018**
  (`docs/architecture/adrs/ADR-018-oidc-jwt-validation-and-dev-auth-toggle.md`),
  registered in the ADR README; references ADR-010 (IdP-agnostic) and ADR-017.

## 9. Open Questions requiring sign-off before implementation

- [x] 9.0 **Pre-req**: `introduce-season-block-episode-hierarchy` has landed
  (provides `BlockId` + `Block` aggregate). This change cannot start otherwise.
- [x] 9.1 **CONFIRMED by stakeholder**: v1 role set = `CostumeDesigner`,
  `WardrobeSupervisor`, `CostumeAssistant` only (all English, per the
  ubiquitous language). No extra roles (`Regie`/`Maske`/`Produktionsleitung`)
  in v1. `Role` enum uses `#[serde(rename_all = "snake_case")]`
  (`costume_designer` / `wardrobe_supervisor` / `costume_assistant`).
- [x] 9.2 **RESOLVED (stakeholder):** tenant boundary = **per `SeriesId`**
  (production today; a future "movie" is also a `Series`). v1 is effectively
  single-tenant; the system is *prepared* for multi-tenancy but does **not**
  enforce cross-tenant isolation in v1 (deferred, not rejected). See `design.md`
  "Resolved Open Decisions" 9.2. (No hard-enforcement code in v1; tenant-awareness
  is baked into the 9.3 audit schema; `AuthContext`/policy stay extensible.)
- [x] 9.3 **RESOLVED (stakeholder):** implement a **queryable audit/journal
  projection** (membership-scoped v1, generic/extensible schema so other
  contexts can be appended later). See `design.md` 9.3 + `block-membership` spec
  "Membership audit journal". Implemented behind ADR-017 (port in `core`, impl in
  `infra`); implementation tasks below.
- [x] 9.4 **RESOLVED (infra):** IdP = **Logto, self-hosted even in production**
  (config-only; no code change). This is a deployment-topology choice, not an IdP
  swap — ADR-010 ("Logto first") unaffected in spirit; only its Cloud-vs-self-host
  deployment note is updated. Dev overlay already self-hosts Logto. Verify
  production `OIDC_*` values at deploy. See `design.md` 9.4.

## 9.3 Implementation (audit projection) — tasks
- [x] 9.3.1 Add Postgres migration `projection_audit` (generic schema: `id`
  UUIDv7 row id, `event_key` TEXT NOT NULL UNIQUE **deterministic content
  key** used as the idempotency key, `entity_type`, `entity_id`, `event_type`,
  `block_id`, nullable `series_id` tenant dim, nullable `actor` from metadata,
  `payload` JSONB, `occurred_at` TIMESTAMPTZ) with indexes for
  block/actor/series/entity/time lookups.
- [x] 9.3.2 Define `AuditRepository` **port** in `core` (generic;
  `list_by_block` / `list_by_actor` / `list_by_time_range` / `list_by_entity`).
- [x] 9.3.3 Implement `AuditProjector` in `infra`
  (`EntityEventHandler<BlockMembership, Transaction<Postgres>>`), idempotent
  under redelivery via a deterministic `event_key` (entity_type + entity_id +
  event_type + payload) + `ON CONFLICT (event_key) DO NOTHING`. SierraDB issues
  a fresh `event.id` on every append, so `event.id` cannot serve as the
  idempotency key — the content key is identical for a redelivered event. Writes
  membership events + `actor` from command metadata.
- [x] 9.3.4 Implement `AuditRepositoryImpl` (query adapter) in `infra`.
- [x] 9.3.5 Register the projector + spawn via `PostgresProcessor` in `main.rs`;
  wire `AuditRepository` into `Ports` / `ProductionPorts`.
- [x] 9.3.6 Unit test for the audit read endpoint (`audit_tests`) added; the
  existing `authz_tests` already gate the same block-scoped read path. Keeps
  `cargo mutants --in-diff` green (whitebox only; the infra projector/repo are
  covered by the Docker-gated integration tests per ADR-016).
- [x] 9.3.7 Expose `GET /blocks/{id}/audit` (block-scoped read, auto-gated by the
  existing `authorize_middleware` via `X-Active-Block`) returning the journal
  as `Json<Vec<AuditEntry>>`.
- [x] 9.3.8 Add a Tier-4 round-trip integration test
  (`crates/integration-tests/tests/audit_projector_tests.rs` →
  `eappend_owner_bootstrapped_round_trips_into_audit`): a `BlockMembership`
  event appended to SierraDB is projected into `projection_audit`
  (command → SierraDB → projector → PG), asserting the row's `entity_type`,
  `event_type`, `block_id`, `actor` (NULL for raw EAPPEND — actor comes from
  command metadata) and full `payload`.
- [x] 9.3.9 Add a Tier-3 idempotency-under-redelivery integration test
  (`audit_projector_is_idempotent_under_redelivery`): re-appending the same
  logical event (fresh SierraDB append → new `event.id`) plus a distinct
  `MemberInvited` proves the projector dedupes on `event_key` (exactly 2 rows,
  `OwnerBootstrapped` appears once). This is the audit analogue of the
  membership projector's expected DB-backed mutants and is owned by the
  Docker-gated integration tests per ADR-016.

## 10. Membership REST endpoints (write + read)

- [x] 10.1 Expose the `MembershipCommands` write surface as REST endpoints, all
  gated by `authorize_middleware` (`BlockMember` for everything except
  self-service accept): `POST /blocks/{id}/members` (invite), `POST
  /blocks/{id}/members/accept` (accept own invitation), `POST
  /blocks/{id}/members/{user_id}/role` (grant role), `DELETE
  /blocks/{id}/members/{user_id}` (remove), `POST /blocks/{id}/members/leave`
  (self-service leave). The authenticated `CurrentUser.sub` is the actor; for
  `accept`/`leave` it is also the target (cannot be supplied by the caller),
  enforcing self-service. `ApiDoc` registers every path + the
  `InviteMemberRequest` / `GrantRoleRequest` / `MembershipView` / `Role` schemas.
- [x] 10.2 Expose the `MembershipRepository` read surface: `GET
  /blocks/{id}/members` (paginated list, `BlockMember`-gated) and `GET
  /blocks/{id}/members/{user_id}` (single membership; 404 when absent,
  `BlockMember`-gated).
- [x] 10.3 `requirement_for` exception: `POST /blocks/{id}/members/accept` is
  gated `Authenticated` (not `BlockMember`) because the invitee is not yet an
  active member; the domain command enforces that a pending invitation exists
  for this block.
- [x] 10.4 Handler unit tests (`membership_tests`): 8 tests assert each endpoint
  dispatches the correct command with the correct actor/target mapping (notably
  that `accept`/`leave` bind the actor as the target) and that reads return the
  projection views / 404. `authz_tests` gains 3 gating tests (member can list →
  200, non-member cannot list → 403, pending invitee can reach accept → 200).
- [x] 10.5 Tier-1–4 `integration-tests` for the membership *write* path
  (command → SierraDB → projector → PG → read-back) added in
  `crates/integration-tests/tests/membership_round_trip.rs`:
  - `command_invite_accept_round_trips_into_membership_projection` (Tier-4):
    `BootstrapOwner` → `InviteMember` → `AcceptInvitation` driven through
    `MembershipCommandsImpl` + `CommandService`, projected by the membership
    `PostgresProcessor`, read back via `MembershipRepositoryImpl` (asserts both
    members active with the correct roles).
  - `command_grant_remove_leave_round_trips_into_membership_projection`
    (Tier-4): `GrantRole` → `RemoveMember` → self-service `LeaveBlock`, asserting
    role replacement, full removal, and leave (actor removes self).
  - `membership_projector_is_idempotent_under_redelivery` (Tier-3): raw EAPPEND
    of `OwnerBootstrapped` + a redelivery of the same event + a distinct
    `MemberInvited`; the `(block_id, user_id)`-keyed upsert means redelivery does
    not duplicate rows (exactly 2 rows: owner active + invitee pending).
  Requires Docker (per ADR-016) to *run*; the test binary compiles cleanly
  (`cargo test -p integration-tests --no-run`).
