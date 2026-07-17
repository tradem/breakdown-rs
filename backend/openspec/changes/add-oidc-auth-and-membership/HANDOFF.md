# Handoff — OpenSpec change `add-oidc-auth-and-membership`

> **This file is a working scratch document for handing the change to a fresh coding
> session. It is NOT part of the OpenSpec change archive and should be deleted after
> the change is archived.** It is intentionally self-contained so a new session can
> deliver Sections 4–9 at full quality without re-deriving prior decisions.

## 0. TL;DR for the next session

- Continue the OpenSpec change **`add-oidc-auth-and-membership`** in this workspace.
  The recommended way to pick it up is the skill **`/opsx-apply`** (change auto-selected
  because it is the only in-progress change), then implement the remaining tasks.
- **Sections 1, 2, 3, and 9.0 are DONE and compile** (`cargo build -p infra -p api` is green;
  `cargo test -p breakdown_core` passes 13 membership tests). Do not redo them.
- **Sections 4, 5, 6, 7, 8 remain**, plus human sign-offs 9.1–9.4 (you cannot complete those).
- Six design decisions (D1–D6) were already resolved during Sections 1–3 and are recorded
  in `design.md` ("Resolved Implementation Decisions"). Honor them — do not re-litigate.
- **One genuine design gap remains open**: how the *first* active member of a block is
  bootstrapped (the API layer gates `InviteMember` behind active-membership, so nothing
  can seed the first member). Resolve this with the user before implementing membership
  management endpoints. See §4 of this doc.

## 1. What is already built (do not redo)

### Section 1 — `UserId` (shared primitive)
- `crates/core/src/shared.rs`: `pub struct UserId(pub String)` — `#[serde(transparent)]`,
  `ToSchema`, `Display`, `FromStr`, `from_sub(String)`, `as_str()`. Unit-tested (1.1/1.2 ✅).

### Section 2 — `membership` Bounded Context (core domain) ✅
- `crates/core/src/membership/{mod,error,events,commands,views,ports,aggregate}.rs`
  - `Role` enum: `Kostümbildner`, `Garderobier` (serde unit variants → `"Kostümbildner"` etc.).
  - `MembershipEvent`: `MemberInvited`, `InvitationAccepted`, `RoleGranted`, `MemberRemoved`.
  - `BlockMembership` aggregate: `Entity`, `ID = Uuid` (stream id = `BlockId.0`),
    `Event = MembershipEvent`, `Metadata = MembershipMetadata { actor: Option<UserId> }`.
    `apply` is idempotent (`match` without catch-all, mirroring `SceneAggregate`).
  - Commands `InviteMember` / `AcceptInvitation` / `GrantRole` / `RemoveMember` / `LeaveBlock`
    implemented with all rejection rules from the spec. `LeaveBlock` derives the leaving user
    from `cmd.metadata().actor` (no `user_id` in payload).
  - `MembershipView { block_id, user_id, role, state: MembershipStateKind, joined_at }`,
    `MembershipStateKind { Pending, Active }` (snake_case serde).
  - `MembershipError` (thiserror, 6 variants) + `From<MembershipError> for DomainError`.
  - Port traits `MembershipCommands` (every method takes `actor: UserId` first) and
    `MembershipRepository` (`find`, `list_by_block`, `is_active_member`).
- 13 unit tests pass (`cargo test -p breakdown_core membership::`).

### Section 3 — Membership infrastructure (infra + api wiring) ✅
- Migration `crates/infra/migrations/20250628000001_membership_projection.up.sql`
  (+`.down.sql`): table `projection_membership(block_id UUID, user_id TEXT, role TEXT,
  state TEXT, joined_at TIMESTAMPTZ, updated_at TIMESTAMPTZ, PK(block_id, user_id))`.
  `role`/`state` stored as their **serde-JSON string form** (`"Kostümbildner"`, `"pending"`).
- `crates/infra/src/projectors/membership.rs`: `MembershipProjector` — `EntityEventHandler<BlockMembership, Transaction<Postgres>>`,
  idempotent under redelivery (upsert on invite; idempotent UPDATE on accept/grant;
  DELETE on remove). Mirrors `block.rs`.
- `crates/infra/src/projectors/mod.rs`: registered `MembershipProjector`, added
  `MembershipProcessor = PostgresProcessor<(BlockMembership,), MembershipProjector>` and
  `spawn_membership_projector(pool, redis_client)`.
- `crates/infra/src/queries/membership.rs`: `MembershipRepositoryImpl(PgPool)` implements
  `MembershipRepository`. `map_membership_row` parses `role`/`state` back via `serde_json`.
- `crates/infra/src/event_store/command_adapters.rs`: `MembershipCommandsImpl` implements
  `MembershipCommands`; each method dispatches `BlockMembership::execute(&cmd_service, cmd.block_id.0, cmd).expected_version(ExpectedVersion::Any).metadata(MembershipMetadata { actor: Some(actor) })`
  and maps the result via the existing `map_executed_result` helper (discards the version → `Ok(())`).
- `crates/infra/src/event_store/mod.rs` re-exports `MembershipCommandsImpl`.
- `crates/api/src/state.rs`: `Ports` trait gained `MembershipCommands`/`MembershipRepo`
  associated types + accessors; `ProductionPorts` gained the two fields, constructor params,
  initializer, and `Ports` impl.
- `crates/api/src/main.rs`: spawns the membership projector and constructs
  `MembershipCommandsImpl` + `MembershipRepositoryImpl` into `ProductionPorts`.

### Section 9.0 — Prerequisite ✅
`BlockId` + `Block` aggregate already land (from `introduce-season-block-episode-hierarchy`).

## 2. Resolved design decisions (recorded in `design.md`, honor them)

- **D1 — JWT crate:** `jsonwebtoken` (validation) + `reqwest` (JWKS fetch). Injectable
  `trait JwksProvider { async fn decoding_keys(&self) -> Result<HashMap<String, DecodingKey>> }`;
  `CachingJwksProvider` caches from `OIDC_JWKS_URL` in a `tokio::sync::RwLock` with ~1h TTL.
- **D2 — Active-Block transport:** request header `X-Active-Block: <BlockId>`, parsed by an
  Axum `FromRequestParts` extractor `ActiveBlock(BlockId)` returning `400` on malformed/missing.
- **D3 — Audit metadata:** `MembershipMetadata { actor: Option<UserId> }`; aggregates read
  `cmd.metadata().actor`. `LeaveBlock` uses the actor as the leaving user.
- **D4 — `Entity::ID = Uuid`** stream id; `BlockId` is a domain field. Dispatch uses
  `cmd.block_id.0` as the stream id (one stream per block).
- **D5 — `core` boundary (ADR-017):** `core` must stay free of `sqlx`/`axum`/`redis`/`sierradb-client`/`tokio`.
  Define the `AuthorizationPolicy` **port trait** + `PolicyDecision` **enum** in `core`; put the PEP
  middleware, `JwksProvider`, `CurrentUser` extractor, and `OidcConfig` in `api`. Serde forms:
  `Role`→`"Kostümbildner"`/`"Garderobier"`; `MembershipStateKind`→`pending`/`active`.
- **D6 — `kameo_es` patch parity:** the local patch lives in `.patches/kameo_es`
  (`kameo = "0.15"`, edition 2021). Keep `Aggregate::execute(&CommandService, stream_id: Uuid, cmd).expected_version(..).metadata(..)` parity.

## 3. Hard constraints (do not violate)

1. **Never add `sqlx`/`axum`/`redis`/`sierradb-client`/`tokio` to `crates/core`.** The
   architecture tests (`cargo test -p architecture_tests`, ADR-017) will fail. The
   `AuthorizationPolicy` port + `PolicyDecision` go in `core`; everything else auth-related in `api`.
2. **ID generation is UUIDv7 only** (`uuid::Uuid::now_v7()`); never v4.
3. **Aggregate `apply` must stay idempotent** — no catch-all arm (mirror `SceneAggregate`).
4. **Write path is CQRS:** never mutate state outside commands; never read aggregates for views
   (use the `MembershipRepository` projection).
5. **Integration tests are Docker-gated** (Postgres + SierraDB `tqwewe/sierradb:0.3.1`) and live in
   `crates/integration-tests`. They are **excluded from `cargo mutants`**; only whitebox
   `#[cfg(test)]` modules are mutated.
6. **The `kameo_es` patch** must remain in sync if you touch aggregate/command traits.
7. **No secrets hardcoded** — `gitleaks` must pass. OIDC config comes from env vars only.

## 4. OPEN DESIGN GAP — resolve before building membership endpoints ⚠️

The API-layer authorization (Section 5) gates **every** block-scoped write/read behind
"caller is an active member of the active block". But nothing in the spec seeds the **first**
active member: to `InviteMember` you must already be an active member (enforced at the API
layer), yet membership can only be created via `InviteMember` → `AcceptInvitation`. Classic
chicken-and-egg. Options to present to the user (do NOT pick silently):

- **(A) Block creator auto-becomes owner:** when a `Block` is created, derive the actor
  (`UserId`) and emit a bootstrap event that makes them an active `Kostümbildner`. Cost: the
  `BlockCreated` event and `Block` write adapter need to carry/preserve the actor; touches the
  `block` BC and its projector. Heavier but cleanest.
- **(B) Zero-member bootstrap:** when a block has **zero** members, the API layer allows any
  authenticated user to `InviteMember`/`AcceptInvitation` (special-case the policy for empty blocks).
  Lightweight, but lets the first random user claim ownership — may need an extra guard.
- **(C) Dedicated bootstrap command/endpoint** (e.g. `SeedBlockOwner`) callable only when the
  block is empty. Explicit, but adds a command not in the current spec.

Recommend asking the user which they prefer (and whether the block creator's identity is even
available at `BlockCreated` time). Do not implement membership *management* HTTP endpoints until
this is settled, or you will build on a hole.

> Note: the existing tasks (5.3/5.4) say "gate write-command endpoints / gate block-scoped read
> endpoints" but there is **no explicit task creating membership-management REST routes**
> (invite/accept/grant/remove/leave/list). Decide with the user whether those endpoints are in
> scope for this change or a follow-up, and if in scope, add tasks for them.

## 5. Remaining task guidance (Sections 4–8)

### Section 4 — OIDC authentication (api layer)
- 4.1: implement D1 (`jsonwebtoken` + `reqwest` + injectable `JwksProvider`). Document in `design.md`.
- 4.2: Axum **`AuthLayer`** (runs first). Validates JWT `iss`/`aud`/`exp` + signature using the
  cached JWKS. On success inserts `CurrentUser { sub: UserId, email: Option<String> }` into
  request extensions. Also parse `X-Active-Block` here (or in the extractor) so downstream layers
  have it. Returns `401` for missing/expired/invalid token, `400` for malformed `X-Active-Block`,
  **`503` for unrecoverable JWKS fetch failure** (4.4).
- 4.3: `CurrentUser` `FromRequestParts` extractor (reads from extensions; `401` if absent — only
  used on endpoints that require auth).
- 4.5 / 4.6: `OidcConfig { iss, audience, jwks_url }` from env (`OIDC_ISS`, `OIDC_AUDIENCE`,
  `OIDC_JWKS_URL`). Dev-mode dummy `CurrentUser` behind a `#[cfg(feature="dev-auth")]` flag / env
  var **never enabled in prod** (used by 6.4 and unit tests).
- 4.7: unit tests for every branch (valid / missing / expired / bad-signature / JWKS-failure).
  Use an injected static `JwksProvider` with a test key; sign test JWTs with `jsonwebtoken`.

### Section 5 — Authorization policy (api layer, action-scoped, block-scoped)
- 5.1: D2 (header transport) — already decided; record in `design.md`.
- 5.2: **`AuthorizationPolicy` port in `core`** (D5) + concrete impl in `api` that resolves the
  active `BlockId` (from `X-Active-Block` / `ActiveBlock` extractor) and calls
  `MembershipRepository::is_active_member(block_id, caller)`; maps to `PolicyDecision::{Allow, Deny}`.
  Keep it **infallible** (every error → `Deny`).
- 5.3 / 5.4: an **`AuthorizationLayer`** (Axum `from_fn`) that runs *after* `AuthLayer`, reads
  `CurrentUser` + `ActiveBlock` from extensions, derives the action from the matched route id +
  HTTP method, and calls the policy. **Panic-resistance (AC5, critical):** wrap the async policy
  call in `tokio::task::spawn(std::panic::AssertUnwindSafe(|| policy.authorize(...)))` and
  `.await.unwrap_or(PolicyDecision::Deny)` — a panicking policy MUST yield `403`, never `500`.
  Missing extensions → `Deny` (defensive). On `Deny` return `403`.
- 5.5: when forwarding a write command, attach the acting `UserId` as `kameo_es` metadata
  (via the `MembershipCommands`/`*CommandsImpl` adapters which already thread `actor`). Leave
  command payloads unchanged.
- 5.6: runtime feature flag flipping "log-only" ↔ "enforce" (see `design.md` Migration Plan).

### Section 6 — Integration tests (Docker-gated, excluded from mutants)
- 6.1: membership command/event sequences (Tier 1–3 Postgres-only).
- 6.2: Tier-4 round-trip `membership` command → SierraDB → projector → Postgres read.
- 6.3: Tier-4 idempotency-under-redelivery (mirror existing redelivery tests).
- 6.4: API-layer test using the dev-mode dummy `CurrentUser` asserting 401/403/200 for at least
  one write and one read endpoint.

### Section 7 — Architecture & guardrails
- 7.1: extend `rust_arkitect` / `cargo test -p architecture_tests` to assert `core` still has no
  `sqlx`/`axum`/OIDC-crate dep after adding `membership` + `UserId` + the `AuthorizationPolicy` port.
- 7.2: `cargo deny check bans` + security audit pass with the new OIDC/validation crates.
- 7.3: `cargo mutants --in-diff` stays scoped to whitebox tests; add membership unit tests to the
  mutation surface (they already exist in `core`).
- 7.4: `./scripts/add-spdx-headers.sh` over new `.rs` files.

### Section 8 — Documentation
- 8.1: `AGENTS.md` §6 — new env vars + dev-mode `CurrentUser` toggle.
- 8.2: `ApiDoc` (utoipa) — membership endpoints + `CurrentUser`/401/403 responses.
- 8.3: ADR (or amend ADR-010) recording the JWT-crate decision + dev-mode auth toggle.

### Section 9 — Sign-offs (you cannot complete these)
- 9.1–9.4 are **human** sign-offs (role set, theater-as-tenancy, audit storage, IdP choice).
  Leave them `[ ]` and surface them to the user; do not fake completion.

## 6. Definition of done / verification before archiving

Run and keep green:
```
cargo build --workspace
cargo test -p breakdown_core            # domain unit tests (incl. 13 membership)
cargo test -p architecture_tests        # ADR-017 boundary
cargo deny check bans                   # dependency policy
cargo mutants --in-diff                 # mutation coverage of changed code
./scripts/add-spdx-headers.sh crates/core/src/membership crates/api/src/auth   # if new dirs
```
Integration tests (Section 6) need Docker + Hub access; run `cargo test -p integration-tests`
when a container runtime is available. `gitleaks` must pass (no hardcoded secrets).

Update `tasks.md` as you go (mark `[x]`). When all implementable tasks are `[x]` and sign-offs
are surfaced to the user, run the **`openspec-sync-specs`** skill (sync deltas → main specs) and
then **`openspec-archive-change`** (only after human sign-off).

## 7. Ready-to-paste prompt for the fresh session

```
Continue the OpenSpec change `add-oidc-auth-and-membership` in /home/digiwitcher/Projekte/repos/breakdown-rs/backend.
Use the `openspec-apply-change` skill (the change auto-selects as the only in-progress one).

STATUS: Sections 1, 2, 3 and task 9.0 are DONE and compile. Do NOT redo them. Sections 4, 5, 6, 7, 8
remain, plus human sign-offs 9.1-9.4 (cannot be completed by you — surface them).

READ FIRST (self-contained context is in):
  openspec/changes/add-oidc-auth-and-membership/HANDOFF.md        # full plan, decisions, gaps
  openspec/changes/add-oidc-auth-and-membership/design.md         # incl. "Resolved Implementation Decisions" D1-D6
  openspec/changes/add-oidc-auth-and-membership/tasks.md          # task checklist
  openspec/changes/add-oidc-auth-and-membership/specs/{oidc-authentication,api-authorization,block-membership}/spec.md

HONOR these resolved decisions (do not re-litigate): JWT crate = jsonwebtoken+reqwest behind
injectable JwksProvider (D1); active-Block = `X-Active-Block` header parsed by an Axum extractor (D2);
audit metadata = MembershipMetadata{actor: Option<UserId>} (D3); Entity::ID = Uuid stream id with
BlockId as a domain field (D4); core must stay free of sqlx/axum/redis/sierradb-client/tokio — only the
AuthorizationPolicy PORT + PolicyDecision live in core, the PEP/JwksProvider/CurrentUser/OidcConfig live
in api (D5); keep kameo_es patch parity in .patches/kameo_es (D6).

CRITICAL OPEN GAP: nothing seeds the FIRST active member of a block (invitation is gated by
active-membership at the API layer → chicken-and-egg). RESOLVE THIS WITH THE USER before building
membership-management endpoints. Present options (A) block creator auto-owner, (B) zero-member
bootstrap allowance, (C) dedicated bootstrap command. Do not pick silently.

QUALITY BAR: produce a correct, tested solution. No shortcuts from context pressure. Keep aggregate
`apply` idempotent (no catch-all), UUIDv7 only, CQRS write/read separation, no secrets hardcoded.
The authorization PEP MUST never panic: wrap the async policy call in tokio::task::spawn(AssertUnwindSafe(...))
and .await.unwrap_or(PolicyDecision::Deny) so a panicking policy yields 403, not 500.

VERIFY before declaring done: cargo build --workspace; cargo test -p breakdown_core;
cargo test -p architecture_tests; cargo deny check bans; cargo mutants --in-diff.
Integration tests (Section 6) need Docker; run cargo test -p integration-tests when available.
Update tasks.md as you implement. Do not fake the 9.1-9.4 sign-offs.
```

---

## 10. Deferred work — membership-management REST endpoints (handoff prompt)

> **Ready-to-paste prompt for the next session.** Sections 1–8 of
> `add-oidc-auth-and-membership` are implemented and green (build,
> `cargo test -p breakdown_core`, `cargo test -p api`, `cargo test -p
> architecture_tests`, `cargo deny check bans`, `cargo mutants --in-diff`).
> The OIDC auth layer + the block-membership authorization gate are
> LIVE, and the first active member is seeded via **bootstrap (Option A)**:
> `create_block` → `BootstrapOwner` → `OwnerBootstrapped`
> (default role `CostumeAssistant`), so no membership endpoint is
> needed to seed the owner. **What remains is exposing the membership
> commands as REST endpoints** — explicitly deferred by the stakeholder.

**Paste this to start the follow-up session:**

```text
Continue the OpenSpec change `add-oidc-auth-and-membership` in
/home/digiwitcher/Projekte/repos/breakdown-rs/backend (workspace root).
Sections 1–5, 7, 8 are DONE and green; Section 6.4 (API-layer
authz test) is DONE. The remaining work is the membership-management
REST API (deferred by the stakeholder — implement it now):

GOALS
1. Expose the existing `MembershipCommands` (InviteMember,
   AcceptInvitation, GrantRole, RemoveMember, LeaveBlock, BootstrapOwner)
   and the read side (`MembershipRepository::list_by_block`, `find`)
   as REST endpoints on the `api` router, gated by the
   already-live `authorize_middleware` (active block via the
   `X-Active-Block` header; 403 for non-members; 400 on a
   missing/malformed header).
2. Add the matching `utoipa`/`OpenAPI` entries to `crates/api/src/lib.rs`
   `ApiDoc` (paths + request/response schemas) and a `swagger-ui` check.

CONSTRAINTS (ADR-017 / locked decisions)
- `breakdown_core` MUST stay free of `sqlx`/`axum`/`redis`/
  `sierradb-client`/`tokio`. The domain ports
  (`MembershipCommands`, `MembershipRepository`) and the
  `AuthorizationPolicy` port + `PolicyDecision` already live in `core`.
- Keep the `kameo_es` patch parity in `.patches/kameo_es`.
- UUIDv7 only (`Uuid::now_v7()`). CQRS: commands go through
  the aggregate + event store; reads hit the Postgres projection.
- The authenticated actor is `CurrentUser { sub: UserId }`
  (extracted from the bearer `sub`), attached by `auth_middleware`.
  Routed write commands must attach it as `kameo_es`
  `Metadata` (`MembershipMetadata { actor: Option<UserId> }`)
  for audit — command payloads stay unchanged.
- Panic-safety: the PEP already wraps the async policy call in
  `tokio::task::spawn(AssertUnwindSafe(...)).await.unwrap_or(Deny)`
  → a panicking policy yields 403, never 500.

WHERE THINGS LIVE
- Core BC: `crates/core/src/membership/{mod,aggregate,commands,
  events,error,ports,views,policy}.rs` (Role = CostumeDesigner /
  WardrobeSupervisor / CostumeAssistant; `OwnerBootstrapped` already
  exists for bootstrap).
- Infra: `crates/infra/src/event_store/command_adapters.rs`
  (MembershipCommandsImpl already attaches the actor as metadata),
  `crates/infra/src/queries/membership.rs` (MembershipRepositoryImpl),
  `crates/infra/src/projectors/membership.rs`.
- API: mirror the EXISTING handler shape in
  `crates/api/src/handlers/mod.rs` (`routes()` builds
  `Router<AppState<ProductionPorts>>`; handlers are generic
  `async fn h<P: Ports>(State<AppState<P>>, Json<Req>) -> ApiResult<T>`;
  use `ApiResult<T> = Result<(StatusCode, Json<T>), (StatusCode, Json<ErrorResponse>)>`
  and the `map_err(DomainError)` helper; `require_*` helpers exist
  for season/episode/block scoping). Add the new membership
  routes inside `routes()` and the `AuthorizationState`/`MembershipAuthorizationPolicy`
  gate already applies to them via `app_router`.
- OpenAPI: `crates/api/src/lib.rs` `ApiDoc` `paths(...)` /
  `components(schemas(...))`.
- Tests: add `#[cfg(test)]` handler tests in `handlers/mod.rs`
  reusing the existing `FakePorts` + `test_helpers`
  (`FakeMembershipCommands`, `FakeMembershipRepo` already exist there),
  and extend `crates/api/src/handlers/mod.rs` `authz_tests` if a new
  gating path is needed. Keep `cargo mutants --in-diff` green
  (whitebox `#[cfg(test)]` only; infra DB paths are covered by the
  Docker-gated integration-tests crate per ADR-016).

OPEN HUMAN SIGNOFFS (do NOT fake — surface to stakeholder)
- 9.2: does a "theater" map to a Logto `Organization` holding
  multiple seasons, and is cross-theater isolation required in v1?
  (affects tenancy + the SeriesId/SeasonId scoping story.)
- 9.3: is `kameo_es` command `Metadata` (`actor`) enough audit
  for v1, or is a dedicated queryable audit projection needed?
- 9.4: confirm IdP = Logto Cloud (ADR-010) at landing, or does
  the team switch to Zitadel first? (the `JwksProvider` abstraction
  already keeps the IdP pluggable; config is env-driven.)

VERIFY before declaring done
- `cargo build --workspace`
- `cargo test -p breakdown_core`  (membership unit tests)
- `cargo test -p api`
- `cargo test -p architecture_tests`  (FORBIDDEN_CORE_DEPS unchanged)
- `cargo deny check bans`
- `cargo mutants --in-diff`  (only whitebox `#[cfg(test)]` mutants)
- Integration tests (Tier 1–4) need Docker: `cargo test -p integration-tests`.
```

> **Do not archive the change** until the membership-management
> endpoints above are implemented and the three open sign-offs (9.2–9.4)
> are answered, since they constrain the endpoint/tenancy/audit design.

---

## 11. Open decisions 9.2–9.4 — handoff prompt (new session)

> **Ready-to-paste prompt for a new session.** Sections 1–8 of
> `add-oidc-auth-and-membership` are implemented and green. **9.1 is
> CONFIRMED by the stakeholder** (v1 role set = `CostumeDesigner`,
> `WardrobeSupervisor`, `CostumeAssistant`; English, snake_case on the wire).
> The following three decisions are still OPEN and must be answered before
> they can be fully implemented — they shape tenancy, audit, and the IdP
> runtime. This prompt hands those open points to a fresh session together
> with the context needed to decide + implement.

**Paste this to start the open-decisions session:**

```text
Workspace: /home/digiwitcher/Projekte/repos/breakdown-rs/backend
OpenSpec change: `add-oidc-auth-and-membership`

CONTEXT (already done, do not redo)
- OIDC auth + block-membership authorization gate are LIVE
  (api/src/auth/*, api/src/auth/authorization.rs, core/src/membership/policy.rs).
- Bootstrap (Option A): `create_block` → `BootstrapOwner` → `OwnerBootstrapped`
  (default role CostumeAssistant) seeds the first owner; no membership
  endpoint needed to seed.
- Role set is CONFIRMED: CostumeDesigner / WardrobeSupervisor / CostumeAssistant
  (snake_case). 9.1 is closed.
- Core MUST stay free of sqlx/axum/redis/sierradb-client/tokio (ADR-017;
  enforced by architecture_tests + deny.toml). Only the `AuthorizationPolicy`
  port + `PolicyDecision` live in core; `JwksProvider`/`OidcConfig`/
  `CurrentUser`/`MembershipAuthorizationPolicy` live in api.
- kameo_es patch parity is kept in `.patches/kameo_es`. UUIDv7 only. CQRS:
  commands → aggregate + event store; reads → Postgres projection.

OPEN DECISIONS TO RESOLVE + IMPLEMENT
These were deliberately surfaced, not faked. For each, get the stakeholder
answer (or confirm the stated default), then implement the chosen design and
update the spec deltas + `design.md` accordingly.

9.2 — Tenancy: does a "theater" map to a Logto `Organization` holding
     multiple seasons/blocks, and is cross-theater isolation required in v1?
   - If YES: the authorization `AuthContext`/membership scoping currently
     keys on `UserId` + active `BlockId` only. You'll likely need a
     tenant/series scope (SeriesId/SeasonId) threading through
     `core/src/membership/policy.rs` `AuthContext`, the
     `MembershipAuthorizationPolicy`, and the `X-Active-Block` extractor
     (or an `X-Active-Series` header). Membership read model
     (`infra/src/queries/membership.rs`) + projection may need a tenant column.
   - If NO (single-tenant v1): leave as-is; just document the assumption.
   - CODE IMPACT: `core/src/membership/{policy.rs,ports.rs,aggregate.rs}`,
     `api/src/auth/authorization.rs`, `api/src/auth/mod.rs` (ActiveBlock /
     new extractor), `crates/infra/src/queries/membership.rs`, migration.

9.3 — Audit: is `kameo_es` command `Metadata` (`MembershipMetadata
     { actor: Option<UserId> }`) enough for v1, or is a dedicated queryable
     audit projection needed?
   - If Metadata is enough: no work; document it (matches current `MembershipCommandsImpl`
     which attaches `cmd.metadata().actor`).
   - If a dedicated audit projection is needed: add a new projector + read
     model (mirror `crates/infra/src/projectors/membership.rs` + the ADR-016
     idempotent-redelivery pattern), a Postgres migration, and wire it into
     `PostgresProcessor` in main.rs. Keep the domain free of sqlx
     (port in core, impl in infra).
   - CODE IMPACT: new `crates/infra/src/projectors/audit.rs`,
     `crates/infra/src/queries/audit.rs`, migration, main.rs wiring,
     possibly a new core `audit` module/port.

9.4 — IdP: confirm Logto Cloud at landing (ADR-010), or does the team
     switch to Zitadel before this ships?
   - The `JwksProvider` abstraction (api/src/auth/jwks.rs) + env-driven
     `OIDC_ISS`/`OIDC_AUDIENCE`/`OIDC_JWKS_URL` already make the IdP pluggable;
     a Zitadel swap is config-only (different JWKS URL/iss/aud). Confirm the
     production env values and, if Zitadel, verify its JWKS/claim shape
     (aud as array, etc.) against `api/src/auth/mod.rs` `AuthState::new`
     `Validation`. No code change expected unless claims differ.
   - CODE IMPACT: likely none (config only); only `AGENTS.md`/deploy docs +
     a dev overlay note if needed.

DELIVERABLES for this session
- Written decisions for 9.2–9.4 (update `design.md` + the three spec deltas
  `specs/{oidc-authentication,api-authorization,block-membership}/spec.md`).
- If 9.2/9.3 require code: implement behind ADR-017, extend the existing
  handler/authz tests (handlers/mod.rs `authz_tests`, api `test_helpers`
  `FakePorts`/`FakeMembership*`), and keep `cargo mutants --in-diff` green
  (whitebox `#[cfg(test)]` only).
- Update `tasks.md`: close 9.2–9.4 once answered. Do NOT fake sign-off —
  mark them OPEN until the stakeholder answer is recorded.

VERIFY before declaring done
- `cargo build --workspace`
- `cargo test -p breakdown_core`
- `cargo test -p api`
- `cargo test -p architecture_tests`   (FORBIDDEN_CORE_DEPS unchanged)
- `cargo deny check bans`
- `cargo mutants --in-diff`
- Integration tests (Docker): `cargo test -p integration-tests`
```

> **Do not archive the change** until 9.2–9.4 are answered AND (if they
> require code) implemented + verified; they constrain tenancy, audit, and
> the IdP runtime of the already-shipped auth/membership layer.
