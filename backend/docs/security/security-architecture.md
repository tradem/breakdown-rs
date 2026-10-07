<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: ox-alpha-free (opencode-go) -->
<!-- Co-authored-by: omen-alpha (opencode-go) -->

# Backend Security Architecture & Security-Test Pyramid

**Status**: Authoritative reference
**Epic**: #83 (defensive hardening strategy)
**Related**: ADR-010 (OIDC/IdP), ADR-017 (architecture testing), ADR-018
(JWT validation & dev-auth toggle), ADR-019 (photo context), ADR-031 (error
surface), [SQL safety](README.md)

This document is the single authoritative write-up of the backend's security
architecture and the target security-test pyramid. Invariants that previously
lived only in code comments are first-class here so they are auditable and
reviewable. Every existing control has a one-line entry with a file pointer;
future PRs that touch these areas must keep this page in sync.

---

## 1. Threat model & trust boundaries

### Tenancy

- **Single-tenant v1.** The tenancy seam is the opaque `ProjectId`
  (`crates/core/src/shared.rs`), renamed from `SeriesId` by issue #591
  (ADR-035 D1/S1) — a 1:1 rename of the *term*, not a change of the tenant
  boundary: same UUIDv7 values, same seam, no multi-tenancy change
  (ADR-035 B1). The projection columns and the OpenAPI field names still spell
  it `series_id`; that is a wire-layer detail of the deferred layer-3
  migration, not a second container. Multi-tenancy itself is deferred — see the
  `api-authorization` spec (`openspec/specs/api-authorization/spec.md`).

### Identity trust root

- The **IdP is the trust root for identity** (Logto dev overlay / IdP-agnostic
  production per ADR-010). The backend verifies standard OIDC JWTs and never
  trusts identity attributes from any other channel; `core` only sees an
  opaque `UserId` derived from the `sub` claim.

### Vault credential ownership (ADR-027, issues #552 / #555)

- Every `projection_settings` credential binding carries an `owner` (the
  authenticated principal that dispatched the bind, recovered by the
  projector from the persisted `EventMetadata.actor`). The AI-config API
  edge (`POST /ai-import/config`, `PATCH` when introducing a key) requires
  the resolved binding's owner to match the caller; a foreign-but-valid
  `vault_key_id` surfaces **403 `ai-config.vault-key-forbidden`** — without
  this check a credential-role member could point their own AI jobs at
  another user's live credential (confused deputy / quota + billing abuse).
  Fail closed: a legacy row with unknown owner denies until the operator
  re-projects (rotation deliberately does not backfill — runbook §10).
- The settings credential handlers are owner-scoped as well (issue #555).
  The credential role (`has_active_credential_role`, ADR-028) is a
  *necessary* but not sufficient gate: `GET`, `PATCH /settings/{id}/gdrive`
  and `DELETE /settings/{id}` additionally require
  `projection_settings.owner == caller`, else **403
  `settings.binding-forbidden`** (scoped code, ADR-031, distinct from the
  role denial `settings.forbidden` so the client can render "this credential
  is not yours"). The pre-check runs in the handler — the only legitimate
  read-model consumer (CQRS boundary) — and *before* any Vault write or
  command dispatch, so a foreign `rotate`/`revoke` can neither replace a
  secret nor destroy the superseded/revoked one. Reading the binding
  metadata (including its `vault_key_id`) is owner-scoped for the same
  reason. A legacy `owner IS NULL` row fails closed into the identical 403.
- *Accepted trade-off:* a foreign binding answers `403` where an unknown id
  answers `404`, so a caller holding a binding id can confirm it exists. The
  id is a client-held UUIDv7 (unguessable), and the same path already split
  `404` (unknown) from `409` (revoked / wrong provider) before this change —
  the extra bit is accepted rather than trading a usable denial narrative for
  a hidden `404`.
- The AI import worker deliberately trusts the stored `config.vault_key_id`
  (it is edge-vetted at write time) but keeps the fail-closed shape check —
  a malformed stored reference can never address an arbitrary Vault path
  (`settings_id_from_binding_key` → `None` → validation error).

### Trust boundaries

```
                    ┌──────────────────────────────────────────────┐
  Internet ──HTTP──▶│ TB1: auth_middleware (OIDC/JWKS verify)      │
                    └──────────────────┬───────────────────────────┘
                                       │ authenticated principal
                    ┌──────────────────▼───────────────────────────┐
                    │ TB2: authorize_middleware (membership policy)│
                    └──────────────────┬───────────────────────────┘
                                       │ authorized request
                    ┌──────────────────▼───────────────────────────┐
                    │ Handlers → Commands → Aggregates             │
                    └───────┬──────────────────────────┬───────────┘
                            │ events                   │ queries
                 ┌──────────▼──────────┐    ┌──────────▼──────────┐
                 │ SierraDB            │    │ Postgres            │
                 │ (event store —      │    │ (read model /       │
                 │  UNTRUSTED          │    │  projections)       │
                 │  durability:        │    │                     │
                 │  projectors must be │    │                     │
                 │  idempotent)        │    │                     │
                 └─────────────────────┘    └─────────────────────┘
                            │
                 ┌──────────▼──────────┐
                 │ S3/Garage           │
                 │ (byte store, IAM-   │
                 │  less API-key-based)│
                 └─────────────────────┘
```

| Boundary | Component | Rationale |
|---|---|---|
| TB1 | `auth_middleware` — `crates/api/src/auth/mod.rs::auth_middleware` | Verifies OIDC JWT (signature, `iss`, `aud`, `exp`) before any handler runs. |
| TB2 | `authorize_middleware` — `crates/api/src/auth/authorization.rs::authorize_middleware` | Enforces the membership policy for block-scoped requests after authentication. |
| Event store | SierraDB | Treated as *untrusted durability*: any consumer must assume redelivery/duplication — projectors use version guards to stay idempotent (see AGENTS.md § photo context). |
| Read model | Postgres projections | Derived state only; never authoritative. Least-privilege roles (`breakdown_migrator` DDL vs. `breakdown_app` DML) — see `scripts/postgres-init-roles.sh`. |
| Bytes | Garage (S3-compatible) | IAM-less, API-key-based access via OpenDAL (`PhotoStorage` port); TLS pinned per ADR-024/ADR-025. |

---

## 2. Authorization architecture

### Deny-by-Default

Every API route passes through both middlewares
(`crates/api/src/routes/mod.rs`, `.layer(auth_middleware).layer(authorize_middleware)`).
The **only allowlist** is the declarative path map
`requirement_for()` in `crates/api/src/auth/authorization.rs`.
Its default arm is `Requirement::BlockMember` — an unclassified path is
block-scoped, never open.

### Allowlist exceptions (and why they are safe)

| Path(s) | Requirement | Why safe |
|---|---|---|
| `/swagger-ui`, `/api-docs` | public | Docs only. Implemented as a **path-check inside the middleware**, *not* by omitting the layer — the middleware still runs on every request. (`authorization.rs::authorize_middleware`, `auth/mod.rs::auth_middleware`) |
| `/seasons`, `/series/{id}/membership` (issue #535), `/settings`, `/blocks` (create/list) | `Authenticated` | No existing block membership can be required: creating a block bootstraps its owner; listing by season needs no block scope. The series-membership self-check is tenant-level data the `X-Active-Block` scope says nothing about (it backstops the client-side AUTHZ-GATE mirror); the handler itself performs no privileged action. |
| `/settings/{id}` (`GET`/`DELETE`), `/settings/{id}/gdrive` (`PATCH`) (issue #555) | `Authenticated` + handler gates | Integration-level credentials, not season-scoped (ADR-028), so the middleware cannot gate them. Every handler enforces the credential role (`has_active_credential_role`) *and* per-binding ownership (`projection_settings.owner == caller`) with `// AUTHZ-GATE:` comments — 403 `settings.forbidden` for the role denial, 403 `settings.binding-forbidden` for a foreign or legacy unknown-owner binding. Ownership is checked before any Vault write or command dispatch, so a non-owner can neither read the `vault_key_id` nor rotate/destroy another user's secret. |
| `/costumes/{id}/photos*` (issue #535) | `Authenticated` + handler gate | Handler internally resolves the costume's owning **series** (strict, `series_id_for_costume_strict` — lookup failures answer 500) and calls `has_active_costume_role_in_series` — a costume-dept role (`costume_designer`, `wardrobe_supervisor`, `costume_assistant`) in any active block of the series authorizes, **series-wide**. Returns `403` on denial, `422 costume.container-unresolved` when the costume has neither character nor repertoire (no resolvable container). Marked with `// AUTHZ-GATE:` comments — reviewers grep for them. See [Costume-photo authorization level (issue #535)](#costume-photo-authorization-level-issue-535). |
| `/blocks/{id}/members/accept` | `Authenticated` | The invitee is *not yet* a member (that is the point). The domain command `AcceptInvitation` binds `user_id` to the authenticated `sub`, so a caller can only accept their own invitation. |
| `/ai-import*`, `/report/*.pdf`, `/report/archive` | `Authenticated` + handler gates | Each handler performs season-scoped internal authorization (costume-dept membership / credential role) with `// AUTHZ-GATE:` comments. |
| `/audit` (series-scoped journal) | `Authenticated` + handler gate | The journal is filtered by the `series_id` **query parameter**, so the caller's active block (`X-Active-Block`) is unrelated to the series being read — a middleware `BlockMember` check would give false assurance. `requirement_for` therefore classifies the route `Authenticated` and `get_audit_history` verifies `MembershipRepository::has_active_membership_in_series` itself, returning `403` on denial (issue #342). Its block-scoped twin `/blocks/{id}/audit` stays `BlockMember`. |
| `/ops/projector-health` (issue #409) | `Authenticated` + handler gate | Deployment-scoped infrastructure state (DLQ + checkpoint progress) — no block/season scope applies. The handler verifies `AuthorizationPolicy::authorize_ops` (active `ops_admin` membership in any block, or the `OPS_ADMIN_SUBS` bootstrap allowlist) with `// AUTHZ-GATE:`. The ops capability itself is protected in both directions: it can only be granted **and** only be demoted/removed by existing ops holders (`invite_member` / `grant_role` / `remove_member` guards — a regular block member can neither self-escalate nor strip an ops holder). The `OPS_ADMIN_SUBS` bootstrap allowlist is injected once at API start; revoking a bootstrap subject requires an API restart, membership-based grants are revocable immediately via the membership API. |

### Fail-closed guarantee

A panicking policy must yield `403`, never `500`. The async policy call is
isolated in a spawned task; a panic surfaces as a `JoinError` which maps to
`Deny`:

```rust
// crates/api/src/auth/authorization.rs::authorize_middleware
let decision = tokio::task::spawn(async move { policy.authorize(&ctx).await })
    .await
    .unwrap_or(PolicyDecision::Deny);
```

Any repository error also collapses to `PolicyDecision::Deny` in
`MembershipAuthorizationPolicy::authorize`.

Every handler-internal gate routes its predicate through the shared
`membership_gate` helper (`crates/api/src/handlers/mod.rs`, issue #537) —
fail-closed, but with an honest error surface: a predicate error is logged
(`tracing::error!`) and propagated as 500 `http.internal-error`, never
masquerading as a 403 permission denial:

```rust
// crates/api/src/handlers/mod.rs (pattern for all // AUTHZ-GATE: sites)
membership_gate(
    state
        .ports
        .membership_repo()
        .has_active_membership_in_series(series_id, current_user.sub.clone()),
    || ApiError::Forbidden("…"),
)
.await?;
```

`Ok(false)` is a genuine deny (403 with the site's reason); `Err(_)` still
grants nothing — the fail-closed semantics are intentional — but the outage
becomes traceable. Multi-scope gates (season-scoped costume operations:
detail editing, category, repertoire target season) use `membership_gate_any`
under `authorize_costume_scoped`. The ast-grep rule
`backend/rules/membership-gate.yml` forbids the pre-#537
`.unwrap_or(false)` pattern in production code.

### Costume-photo authorization level (issue #535)

ADR-035 **B2** (normative): authorization predicates are typed by the
*authorization level*, never by a production-form-specific container — and
since #535 the costume-photo gate is typed at the **series/project level**
(`MembershipRepository::has_active_costume_role_in_series`):

- **Predicate + role set.** Same three costume-department roles as the
  season-scoped predicate (`costume_designer`, `wardrobe_supervisor`,
  `costume_assistant`), one level up — the SQL joins
  `projection_membership ⋈ projection_block ON b.series_id` instead of
  `b.season_id`.
- **Scope widening (deliberate, reviewed).** Pre-#535 the gate checked the
  season union (character season ∪ repertoire seasons, `authorize_costume_scoped`)
  per season. Under the series policy, whoever holds a costume-dept role
  *anywhere in the series* can read and manage the photos of **all** costumes
  in that series — including costumes standing in seasons they have no season
  role for. This is defensible because the costume department is
  institutionally a cross-season domain (the `any active block` semantics of
  the existing predicates, the m:n repertoire of #453/#534) and because a
  carried-over costume would otherwise be unmanageable for the wardrobe team
  that brought it in. It is a boundary shift, **not** a mechanical re-bend —
  hence its place in this document.
- **Why the photo gate and not the journal predicate.**
  `has_active_membership_in_series` (the `/audit` gate) stays deliberately
  **role-agnostic** — the audit journal is an operational record of the whole
  production. Photos are a costume-department artefact, so the photo predicate
  keeps the costume-role allowlist even at series level.
- **Domain vs authorization scope.** The costume's repertoire remains its
  *domain* scope — it decides which seasons list the costume and which series
  the costume resolves to. Only the *authorization* level moved up. The
  season union must not be re-introduced as an authorization input, and the
  client gate must not deny on it (AGENTS rule; the client mirrors the series
  predicate via `GET /v1/series/{id}/membership`).
- **Season-scoped gates remain.** Genuinely season-scoped costume operations
  (detail editing #543/#544, `set_costume_category` season-match invariant #543,
  repertoire add/remove on the **target** season #534/#533, continuity photos,
  reports) keep the season-typed predicate `has_active_costume_role_in_season`;
  ADR-035 B2 forbids *adding* new `*_in_season` predicates, not keeping this
  grandfathered one.

## Membership projection encoding (role / state)

`projection_membership.role` and `.state` store **plain tokens**
(`costume_assistant`, `active`), written by
`crates/infra/src/projectors/membership.rs`. The wire form of
`MembershipView` is unchanged serde JSON (`"costume_assistant"`,
`"active"`). Keeping the two apart matters: every membership authorization
predicate compares those columns against plain SQL string literals
(`m.state = 'active'`, `m.role IN ('costume_designer', …)`), so JSON-quoted
values match nothing and the gate denies every caller.

`Role::as_str` / `Role::from_token` and
`MembershipStateKind::as_str` / `MembershipStateKind::from_token` are the
single source for the storage form; `crates/core/tests/membership_projection_tokens.rs`
pins the storage token to the serde form so they cannot drift (found while
implementing issue #342).

### Staged rollout & dev mode

- `AUTHZ_ENFORCE=false` → log-only mode: denials are logged (`AUTHZ(log-only)`),
  requests allowed. Used for staged rollout observation.
- Dev mode (`DEV_AUTH_SUB` set, `OIDC_ISS` unset) defaults enforcement **off**
  so local development works without seeded membership. Production always sets
  `OIDC_ISS` and therefore cannot reach dev mode (ADR-018).

---

## 3. OIDC / JWT validation

Implementation: `crates/api/src/auth/{mod.rs,jwks.rs}` (ADR-010, ADR-018).

| Control | Detail |
|---|---|
| Library | `jsonwebtoken 9`, RS256 only (`Validation::new(Algorithm::RS256)`) |
| Key source | JWKS document fetched via `StaticJwksProvider`, cached by `CachingJwksProvider` (TTL 3600 s, refresh on cache miss **and** on validation failure — key rotation self-heals within one request) |
| Claims enforced | `iss`, `aud`, `exp` |
| Algorithm confusion | Header `alg` must be RS256; unknown `kid` rejects rather than falling back |
| Dev-mode gating | Only reachable when `OIDC_ISS` is unset **and** `DEV_AUTH_SUB` is set — structurally unreachable in production |

---

## 4. SQL safety posture

Full guidelines with safe patterns and a review checklist:
[docs/security/README.md](README.md).

- Every statement passed to `sqlx::query*()` is a **static `&str` literal**;
  all dynamic values go through `.bind()` (`$1` placeholders, runtime-prepared
  — injection-safe because the SQL text is static).
  Implementations live in `crates/infra/src/queries/*.rs`.
- **Hard rule:** no `format!` / string concatenation into SQL statements.
  Identifiers come from hardcoded allowlists only.
- Mechanically enforced by the `no-string-interpolation-sql` CI job
  (`.github/workflows/architecture-checks.yml`).
- Least-privilege Postgres roles: `breakdown_migrator` (DDL, boot-only) vs.
  `breakdown_app` (DML only); the audit table additionally loses
  UPDATE/DELETE at boot (`main.rs` two-pool architecture).
- Migration reversibility is tested in CI (`migrations_are_reversible`,
  Tier-1 testcontainers test) so rollbacks stay deterministic.

---

## 5. Supply chain

| Control | Where | Note |
|---|---|---|
| `unsafe_code = "deny"` | workspace `[workspace.lints.rust]` in `backend/Cargo.toml` | Workspace-level deny is inherited by every crate (stronger than per-crate opt-ins); `forbid` would prevent legitimate local `#![allow(unsafe_code)]` escapes, hence `deny`. |
| Dependency bans | `cargo deny check bans` against `backend/deny.toml` (ADR-017 Layer 1) | Forbids `sqlx`/`axum`/`redis`/`sierradb-client`/`tokio` as dependencies of `core`. |
| Source-level boundaries | `cargo test -p architecture_tests` (`rust_arkitect`, ADR-017 Layer 2) | No forbidden `use` statements under `crates/core/src`. |
| RUSTSEC advisory handling | `[[advisories.ignore]]` in `backend/deny.toml` | Each ignore carries an inline rationale (affected code path not reachable / no patched release / build-time-only) and a "revisit on upgrade" trigger. |
| Secrets | `gitleaks` in CI; Vault for external credentials (ADR-027) | Never hardcode secrets. |
| CI workflow hardening | SHA-pinned third-party actions, `env:` injection instead of expression interpolation | See AGENTS.md § CI hardening; tracked further in epic #83 (#86). |

---

## 6. Security-test pyramid (target)

Status markers: ✅ present · 🟡 partially present (gap tracked) · ⏳ absent
(tracked by another issue in epic #83).

```
            ┌──────────────────────────────────┐
            │  Fuzzing (nightly)               │ ⏳ cargo-fuzz — serde request
            │                                  │    bodies (#91)
            ├──────────────────────────────────┤
            │  Property-based tests            │ 🟡 proptest present
            │                                  │   (crates/core/tests/proptest.rs);
            │                                  │   domain-invariant expansion #89
            ├──────────────────────────────────┤
            │  Mutation testing (in-diff)      │ 🟡 cargo-mutants configured
            │                                  │   (.cargo/mutants.toml, CI-only);
            │                                  │   review gate #90
            ├──────────────────────────────────┤
            │  Integration tests Tier-4        │ ✅ command→SierraDB→projector→PG
            │                                  │   round-trip (testcontainers,
            │                                  │   crates/integration-tests)
            ├──────────────────────────────────┤
            │  Auth tests                      │ ✅ crates/api/tests/
            │  (authz_tests, jwks_test)        │   {auth_authorization.rs,
            │                                  │    auth_jwks.rs, handler_authz.rs}
            ├──────────────────────────────────┤
            │  Architecture tests              │ ✅ cargo-deny + rust_arkitect
            │                                  │   (ADR-017)
            ├──────────────────────────────────┤
            │  Unit tests (core)               │ ✅ crates/core (deterministic
            │                                  │   domain tests)
            └──────────────────────────────────┘
```

Reading order: the base is fully in place; the upper layers (mutation review
gate, property-test breadth, nightly fuzzing) close the remaining gaps and are
tracked individually so this pyramid can be driven to all-green.

---

## Control index (one-line pointers)

| Control | File pointer |
|---|---|
| JWT verification (RS256, iss/aud/exp) | `crates/api/src/auth/mod.rs::auth_middleware` |
| JWKS caching (TTL 3600 s, refresh-on-failure) | `crates/api/src/auth/jwks.rs::CachingJwksProvider` |
| Deny-by-default route classification | `crates/api/src/auth/authorization.rs::requirement_for` |
| Fail-closed policy evaluation | `crates/api/src/auth/authorization.rs::authorize_middleware` (`tokio::task::spawn` + `unwrap_or(Deny)`) |
| Membership policy (block-scoped) | `crates/api/src/auth/authorization.rs::MembershipAuthorizationPolicy` |
| Season-scoped photo policy | `crates/api/src/auth/authorization.rs::SeasonPhotoAccessPolicy` (+ `// AUTHZ-GATE:` markers on handlers) |
| Series-scoped costume-photo policy (issue #535) | `crates/api/src/handlers/mod.rs::authorize_costume_in_series` + `crates/infra/src/queries/membership.rs::has_active_costume_role_in_series` (+ `// AUTHZ-GATE:` markers on the three photo handlers) |
| Middleware layering | `crates/api/src/routes/mod.rs` |
| Static-SQL rule + safe patterns | `docs/security/README.md`; enforced by `no-string-interpolation-sql` job |
| Postgres least-privilege roles | `scripts/postgres-init-roles.sh`, `crates/api/src/main.rs` |
| Migration reversibility test | `crates/integration-tests` (`migrations_are_reversible`) |
| `unsafe_code` lint | `backend/Cargo.toml` `[workspace.lints.rust]` |
| Dependency bans / advisory ignores | `backend/deny.toml` |
| Architecture boundary tests | ADR-017, `crates/architecture-tests` |
| Problem-code error surface (RFC 9457) | `crates/core/src/error_registry.rs`, `crates/api/src/problems` (ADR-031) |
