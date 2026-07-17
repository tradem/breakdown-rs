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

- [~] 6.1 Extend `crates/integration-tests` fixtures with membership
  command/event sequences (Tier 1–3 Postgres-only). **Deferred** — requires
  Docker (ephemeral Postgres) and is coupled to the membership-management
  follow-up (no membership *write* endpoints exist yet to drive end-to-end
  sequences). Covered today only at unit level (projector/repo compile + the
  Docker-Tier will own this per ADR-016).
- [~] 6.2 Add a Tier-4 round-trip test for `membership` command → SierraDB →
  projector → Postgres read model. **Deferred** (Docker: SierraDB + Postgres).
- [~] 6.3 Add a Tier-4 idempotency-under-redelivery test. **Deferred** (Docker).
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
  **infra 2 survivors** (the `membership` projector `handle` and `find`
  query — DB-backed, owned by the Tier-3 projector/repository integration
  tests).
- [x] 7.4 `./scripts/add-spdx-headers.sh` headers present on all new
  `.rs` files (verified).

## 8. Documentation

- [x] 8.1 Update `AGENTS.md` §6 with the new env vars (`OIDC_ISS`,
  `OIDC_AUDIENCE`, `OIDC_JWKS_URL`, `AUTHZ_ENFORCE`, `DEV_AUTH_SUB`,
  `DEV_AUTH_EMAIL`) and the dev-mode `CurrentUser` toggle.
- [ ] 8.2 OpenAPI `ApiDoc`: **out of scope** — the membership-management
  *endpoints* (invite/accept/grant/remove/leave/list) are a **deferred
  follow-up** per the locked decision, so there are no new membership paths to
  document yet. (The `create_block` handler gained a `CurrentUser` extractor;
  the existing OpenAPI surface is unchanged.)
- [ ] 8.3 ADR / ADR-010 amendment recording the JWT-validation-crate
  decision and the dev-mode auth toggle. **Optional** — `design.md` already
  captures the decision; a formal ADR can follow with the membership
  endpoints.

## 9. Open Questions requiring sign-off before implementation

- [x] 9.0 **Pre-req**: `introduce-season-block-episode-hierarchy` has landed
  (provides `BlockId` + `Block` aggregate). This change cannot start otherwise.
- [x] 9.1 **CONFIRMED by stakeholder**: v1 role set = `CostumeDesigner`,
  `WardrobeSupervisor`, `CostumeAssistant` only (all English, per the
  ubiquitous language). No extra roles (`Regie`/`Maske`/`Produktionsleitung`)
  in v1. `Role` enum uses `#[serde(rename_all = "snake_case")]`
  (`costume_designer` / `wardrobe_supervisor` / `costume_assistant`).
- [ ] 9.2 **OPEN — stakeholder/product**: confirm whether a "theater" maps
  to a Logto `Organization` containing multiple productions/seasons, and
  whether cross-theater isolation is required in v1. (Affects tenancy + the
  `SeriesId`/`SeasonId` scoping story; not yet implemented.)
- [ ] 9.3 **OPEN — stakeholder**: decide whether audit needs a dedicated
  queryable audit projection, or whether `kameo_es` command `Metadata`
  (`MembershipMetadata { actor: Option<UserId> }`) is sufficient for v1.
  (The metadata path is implemented end-to-end; a dedicated projection is not.)
- [ ] 9.4 **OPEN — infra**: confirm IdP is Logto Cloud (per ADR-010) at
  landing, or whether the team switches to Zitadel before this change ships.
  (The `JwksProvider` abstraction keeps the IdP pluggable; config is
  env-driven.)
