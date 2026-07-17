## Context

The backend today is fully open: every Axum handler executes without any notion of a caller, and `core`'s Bounded Contexts have no concept of *ownership*, *membership*, or *auditing who acted*. The production hierarchy (`Series`/`Season`/`Block`/`Episode`) is introduced by the sibling change `introduce-season-block-episode-hierarchy`, which this change builds on.

ADR-010 (*Authentication with OpenID Connect*) constrains the solution space decisively:

- **Authentication is externalized.** The backend never handles passwords, MFA, registration, or session storage. It only validates cryptographically signed JWTs issued by an OIDC provider (Logto Cloud first; Zitadel migration later).
- **No IdP-specific SDK in the backend.** Switching IdPs is a configuration change (`iss` + JWKS URL).
- **Multi-tenancy exists at the IdP level** via Logto Organizations.

Stakeholder input (confirmed) refines the original scope: roles are *block-scoped* (`Kostümbildner*in`, `Garderobier*in`) — a person rotates role at Block boundaries, so roles cannot live as IdP-global organization roles, nor even season-global ones. Membership therefore hangs off `BlockId`, and authorization is action-scoped (the active Block of the request). A `Series`/`Season` aggregate remains a future, stakeholder-driven change; meanwhile `BlockId` is opaque to the membership context.

```
   Logto/Zitadel (IdP)              Rust backend
   ─────────────────                ──────────────────────────────────
   • account lifecycle              • validate signed JWT (api layer)
   • passwords, MFA, SSO            • extract CurrentUser { sub, ... }
   • Organizations (tenancy)        • authorize per active-Block (api)
   • global technical admins        • core/membership references sub
                                    as opaque UserId (value type)
   ─ DOES NOT live in core ─        ─ core stays pure domain ─
```

## Goals / Non-Goals

**Goals:**
- Implement the ADR-010 OIDC seam: JWT validation + `CurrentUser` extraction in `crates/api`, with no IdP-specific SDK coupling.
- Introduce a `membership` Bounded Context in `crates/core` modeling **block-scoped** membership and roles, following the established `aggregate/commands/events/error/ports/views` schema.
- Provide an authorization policy in `crates/api` that consults the block-membership read model for the *active Block of the request* before write commands and block-scoped reads.
- Keep `core` free of any identity/account lifecycle concerns. `UserId` is an opaque value type referencing the IdP `sub`.
- Path the existing commands for audit via `kameo_es` command metadata (the `Metadata` type already in use), not by polluting command payloads.

**Non-Goals:**
- The `Series`/`Season` aggregates (name, dates, status, archived flag). They are their own future, stakeholder-driven changes. `BlockId` stays opaque to the membership context.
- Defining the *active-Block* transport: whether the active Block rides in the request path, a header, or a body field is an API-design detail resolved at implementation; the membership context itself only needs `BlockId`.
- Account lifecycle: registration, email verification, password reset, MFA, social login — all IdP territory.
- IdP selection / migration tooling. ADR-010 says Logto first; this change assumes Logto-compatible OIDC and does not build migration tooling.
- A full RBAC/ABAC framework. Authorization is a thin, block-scoped, action-scoped policy in the API layer.
- Finalizing the complete role set. Initial roles `Kostümbildner*in` and `Garderobier*in` are modeled; the role enum is open for extension pending stakeholder confirmation.
- Row-level multi-tenancy across theaters. Tenancy at the IdP `Organization` level is acknowledged but not enforced inside `core` in this change.

## Decisions

### 1. Authentication: validate standard OIDC JWTs in an Axum middleware
**Decision.** A `tower`/Axum middleware fetches and caches the IdP JWKS, verifies token signature, `iss`, `aud`, and `exp`, and inserts a `CurrentUser { sub, email, ... }` into request extensions. Handlers obtain it via an `axum::extract::FromRequestParts` extractor.
**Rationale.** ADR-010 mandates backend-only-JWT-validation with no IdP SDK. A middleware + extractor matches Axum idioms and keeps handlers testable with a fake `CurrentUser`.
**Alternatives considered.** (a) `tower-http`'s auth layers — too generic, would reimplement JWKS caching anyway. (b) `oxide-auth` — an authorization *server*, not what we need; we are a *resource server*. (c) Per-handler validation — scatters logic, easy to forget a handler.

### 2. `UserId` as an opaque core value type, not an aggregate
**Decision.** `crates/core/src/shared.rs` gains `UserId(String)` (the OIDC `sub` claim), mirroring the existing value-type pattern (`ProjectId`, and its successor `BlockId`/`SeasonId`/`SeriesId`). `core` never decodes, validates, or stores identity attributes — it only references `UserId` as a foreign identifier.
**Rationale.** ADR-010 keeps identity out of `core`. Modeling `User` as an aggregate would pull account lifecycle (and security-critical hashing) into the event-sourced domain, conflicting with `core`'s pure-domain stance and complicating `cargo mutants`/security-audit boundaries.
**Alternatives considered.** (a) A separate `crates/identity` crate for an account aggregate — rejected; ADR-010 externalizes accounts entirely, so there is no account aggregate to host. (b) Pass the raw `sub: String` everywhere — rejected; a wrapper gives type safety and consistent serialization with the rest of `shared.rs`.

### 3. `membership` as its own Bounded Context, **block-scoped**
**Decision.** Add `crates/core/src/membership/` with aggregate `BlockMembership`, **scoped per `BlockId`** (one stream per Block), holding a `{ user_id: UserId -> role: Role }` map. The aggregate does not own Block metadata — only membership.
**Rationale.** Stakeholder confirmed costume-department staff *rotate roles at Block boundaries* (a person is `Kostümbildner*in` in Block 1 and `Garderobier*in` in Block 2 of the same season). The Block is therefore the natural authorization scope. A dedicated aggregate per Block keeps command streams focused (no lock contention between membership edits in different Blocks) and avoids embedding membership in a future `Season`/`Series` aggregate where every Block's membership churn would compete for one stream lock.
**Cross-change dependency.** This change requires `introduce-season-block-episode-hierarchy` to have landed first — it introduces the `Block` aggregate and `BlockId` value type on which membership hangs. `BlockId` is an opaque identifier to the membership context, consistent with how the other contexts treat their parent IDs.
**Alternatives considered.** (a) Season-scoped membership — rejected; it cannot represent per-Block role rotation, which the stakeholder explicitly requires. (b) Per-`ProjectId`/`SeriesId`-scoped membership — rejected; same reason. (c) A single membership map keyed by `(user_id, block_id)` on a Season aggregate — rejected on stream-contention grounds (every Block's membership edit contends for the Season lock).

### 4. Roles are domain-local, modeled as an open `enum`
**Decision.** `Role` is an `enum` in `crates/core/src/membership`, initially `Kostümbildner` and `Garderobier`, designed so new variants are additive (backwards-compatible deserialization).
**Rationale.** Roles are **block-scoped** — a person may be `Kostümbildner*in` in Block 1 and `Garderobier*in` in Block 2 of the same season, so they cannot be IdP-global organization roles (nor even season-global). An `enum` gives compile-time exhaustiveness for authorization matching. Extensibility is acceptable as long as additions are purely additive.
**Alternatives considered.** (a) Store roles as IdP Organization roles — rejected; block-scoped roles need per-Block assignment and rotation. (b) `String`/free-form roles — rejected; loses exhaustiveness and weakens the authorization policy. (c) A separate `Role` value object with permission sets — premature; deferred until the role set and permission matrix are stakeholder-confirmed.

### 5. Authorization is **action-scoped** (the active Block), not data-scoped, and lives in `crates/api`
**Decision.** A policy module in `crates/api` queries the block-membership read model for the caller's role in the *active Block of the request* before dispatching write commands (and before returning block-scoped reads), translating a deny decision into HTTP 403. `core` aggregates do not receive the caller and do not enforce authorization. The "active Block" is conveyed by the request (explicit block context in the request path or body, or a UI session scope), NOT derived from the data being mutated.
**Rationale.** Stakeholder: a person works *in a Block* for a stretch of time and their role there governs everything they touch during that stretch. This is action-scoped, not data-scoped — it cleanly resolves the Main-Cast-costume ambiguity (a Main-Cast costume spans multiple Blocks; data-scoping it to one Block is ill-defined, while action-scoping the *edit* to "the block Anna is currently working in" is unambiguous). Authorization in the API layer (not `core`) respects CQRS read/write separation.
**Alternatives considered.** (a) Data-scoped authorization (resolve the data's Block, check membership there) — rejected; fails for Main-Cast Costumes/Characters that span multiple Blocks with no single owning Block. (b) Inject `CurrentUser` into every command and have aggregates self-authorize — rejected; violates CQRS read/write split. (c) Season-scoped authorization — rejected; cannot represent per-Block role rotation.

### 6. Audit via `kameo_es` metadata, not command payload
**Decision.** The acting `UserId` is attached as `kameo_es` command metadata for the write side, allowing event-stream audit ("who emitted this event") without changing the command's domain payload. Existing commands (`CreateScene`, `UpdateCostumeNotes`, …) keep their current signatures.
**Rationale.** The acting user is rarely a *domain* concern of `scene`/`costume`/etc.; it is an audit/observability concern. Metadata preserves clean command payloads and avoids retroactive signature churn across all handlers. Where the actor *is* a domain concern (e.g. a future "only a `Kostümbildner` may finalize a calculation"), that specific command will carry the actor in its payload explicitly — but that is decided per-command, not blanket.
**Alternatives considered.** (a) Add `actor: UserId` to every command payload — rejected; pollutes unrelated commands and bloats event payloads. (b) No audit at all — rejected; multi-user collaboration requires an audit trail.

## Risks / Trade-offs

- [IdP availability is a hard runtime dependency] → If Logto Cloud is down, no request can authenticate. Mitigation: short token TTLs + observability; the middleware returns 503 on JWKS fetch failure rather than 401, so the failure mode is honest. A locally cacheable JWKS reduces blast radius.
- [Local dev friction without a local IdP] → dev compose currently has no IdP. Mitigation: support a "dev mode" accepting a fixed dummy `CurrentUser` behind a feature flag/env var (never enabled in prod), so unit/integration tests stay deterministic. Documented in `AGENTS.md` at implementation time.
- [Membership projector idempotency under redelivery] → same projector-redelivery concern as the existing four projectors. Mitigation: reuse the established idempotency pattern from ADR-016 / `projector-supervision`; add a Tier-4 redelivery test mirroring the existing ones.
- [Role set is not yet stakeholder-confirmed] → adding a role later is additive if the enum stays open, but removing one is a breaking change. Mitigation: only commit `Kostümbildner` + `Garderobier` as the v1 set in the spec; further roles wait for stakeholder sign-off (see Open Questions).
- [Tenancy (`Organization`) inside `core` is deferred] → the membership model is per-`BlockId` and does not yet enforce that a user belongs to the theater owning the season/block. Mitigation: explicit Non-Goal; the IdP organization check happens upstream at login, and per-theater isolation inside the domain is a follow-up change once `Series`↔`Organization` is modeled.
- [Cross-change sequencing risk] → this change depends on `introduce-season-block-episode-hierarchy` landing first (for `BlockId`). Mitigation: documented sequencing in both changes; the hierarchy change's tasks include the handoff note.

## Migration Plan

- Pure addition — no breaking API change unless required by the decision to gate previously-open endpoints. The migration is staged:
  1. **Land `introduce-season-block-episode-hierarchy` first** (provides `BlockId` and the `Block` aggregate). This change cannot compile without it.
2. Ship the OIDC middleware + `CurrentUser` extractor behind a feature flag, with authorization in "log-only" mode (allowing all requests but recording the actor), so existing flows are unaffected.
3. Add the `block-membership` BC + projector + projection migration.
4. Flip authorization from "log-only" to "enforce" for block-scoped endpoints once integration tests cover the policy, including the active-Block context resolution.
- Rollback: keep the feature flag in step 1/3 so enforcement can be disabled at runtime if a policy regression slips through.

## Open Questions

1. **Final role set.** Beyond `Kostümbildner*in` and `Garderobier*in`, are roles like `Regie`, `Maske`, `Produktionsleitung` expected for v1? (Stakeholder.) Determines whether the spec is committed with two roles or a larger set.
2. **Theater-as-tenancy.** Is a "theater" a Logto `Organization` that *contains* multiple productions/seasons, or is each independently accessible? (Stakeholder / product.) Affects whether `Series`/`Season` needs an `organization_id` and whether the membership model needs cross-theater isolation in v1.
3. **Dev-time IdP.** Local dev without Logto Cloud: dummy `CurrentUser` via feature flag, self-hosted Logto container in dev compose, or a tiny mocked JWKS server? (Technical — resolves at design-into-implementation.)
4. **JWT validation crate.** `jsonwebtoken` (manual JWKS caching) vs. a higher-level OIDC resource-server crate. (Technical — resolves at design-into-implementation.)
5. **Audit storage.** Is `kameo_es` metadata sufficient for audit, or do stakeholders need a dedicated, queryable audit projection? (Stakeholder + technical.)

## Resolved Implementation Decisions (during implementation)

These were resolved while building Sections 1–3 and are recorded here so the
remaining Sections 4–9 can proceed without re-deriving them.

### D1 — JWT validation crate (Open Question 4)
Use **`jsonwebtoken`** for signature/claim validation + **`reqwest`** (blocking
or async) to fetch the JWKS document. Wrap key discovery behind an injectable
`trait JwksProvider { async fn decoding_keys(&self) -> Result<HashMap<String, DecodingKey>> }`
so tests can inject a static provider. A `CachingJwksProvider` impl fetches from
`OIDC_JWKS_URL`, caches the key set in a `tokio::sync::RwLock` with a TTL (~1h),
and refreshes on miss / 401-from-validation. Rationale: std/recommended crates,
no heavy opinionated OIDC framework, fully testable. (Decision recorded 2026-06-23.)

### D2 — Active-Block transport (Open Question 2 of the auth spec)
Carry the block context as a request header **`X-Active-Block: <BlockId>`**, parsed
by an Axum extractor `ActiveBlock(BlockId)` that returns `400` on malformed/missing
when a block-scoped endpoint requires it. Rejected alternative: query param (pollutes
URLs/logs, less appropriate for session-scoped context). (Decision recorded 2026-06-23.)

### D3 — Audit metadata (Open Question 5)
Aggregate `Metadata = MembershipMetadata { actor: Option<UserId> }`. The membership
`Command` impls read `cmd.metadata().actor`; `LeaveBlock` derives the leaving user from
the actor (no `user_id` in its payload). Actor is `Some` for all authed requests because
the auth middleware always populates `CurrentUser` before the handler runs.
(Decision recorded 2026-06-23.)

### D4 — `Entity::ID`
Use **`Uuid`** as the `kameo_es` stream id (consistent with every existing aggregate),
with `BlockId` carried as a domain field, not the stream id. `command_adapters` dispatch
with `BlockMembership::execute(&cmd_service, cmd.block_id.0, cmd)` — i.e. the stream id
is the `BlockId`'s inner `Uuid`, and one stream holds exactly one block's membership
aggregate. (Decision recorded 2026-06-23.)

### D5 — `core` boundary (ADR-017)
`core` must NOT depend on `sqlx` / `axum` / `redis` / `sierradb-client` / `tokio`.
Therefore the `AuthorizationPolicy` **port trait** and `PolicyDecision` enum are defined
in `core` (so the domain stays DI-friendly and testable), while the concrete PEP
middleware, `JwksProvider`, `CurrentUser` extractor, and `OidcConfig` live in `api`.
`UserId`, `Role`, `MembershipStateKind` serde forms: `Role` unit variants serialize as
`"Kostümbildner"` / `"Garderobier"`; `MembershipStateKind` is snake_case (`pending` /
`active`). The `projection_membership` row stores these as their serde-JSON string form.
(Decision recorded 2026-06-23.)

### D6 — `kameo_es` patch parity
The local `kameo_es` patch lives in `.patches/kameo_es` and pins `kameo = "0.15"`,
edition 2021. Any change to the aggregate/command traits must keep patch parity
(`Aggregate::execute(&CommandService, stream_id: Uuid, cmd).expected_version(..).metadata(..)`).
