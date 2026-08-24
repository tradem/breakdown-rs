<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: ox-alpha-free (opencode-go) -->

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

- **Single-tenant v1.** The tenancy seam is the opaque `SeriesId`
  (`crates/core/src/shared.rs`); multi-tenancy is deferred — see the
  `api-authorization` spec (`openspec/specs/api-authorization/spec.md`).

### Identity trust root

- The **IdP is the trust root for identity** (Logto dev overlay / IdP-agnostic
  production per ADR-010). The backend verifies standard OIDC JWTs and never
  trusts identity attributes from any other channel; `core` only sees an
  opaque `UserId` derived from the `sub` claim.

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
| `/seasons`, `/settings`, `/blocks` (create/list) | `Authenticated` | No existing block membership can be required: creating a block bootstraps its owner; listing by season needs no block scope. |
| `/costumes/{id}/photos*` | `Authenticated` + handler gate | Handler internally calls `SeasonPhotoAccessPolicy::authorize_season` (costume-dept role in an active block of the season) and returns `403` on denial. Marked with `// AUTHZ-GATE:` comments — reviewers grep for them. |
| `/blocks/{id}/members/accept` | `Authenticated` | The invitee is *not yet* a member (that is the point). The domain command `AcceptInvitation` binds `user_id` to the authenticated `sub`, so a caller can only accept their own invitation. |
| `/ai-import*`, `/report/*.pdf`, `/report/archive` | `Authenticated` + handler gates | Each handler performs season-scoped internal authorization (costume-dept membership / credential role) with `// AUTHZ-GATE:` comments. |

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
| Middleware layering | `crates/api/src/routes/mod.rs` |
| Static-SQL rule + safe patterns | `docs/security/README.md`; enforced by `no-string-interpolation-sql` job |
| Postgres least-privilege roles | `scripts/postgres-init-roles.sh`, `crates/api/src/main.rs` |
| Migration reversibility test | `crates/integration-tests` (`migrations_are_reversible`) |
| `unsafe_code` lint | `backend/Cargo.toml` `[workspace.lints.rust]` |
| Dependency bans / advisory ignores | `backend/deny.toml` |
| Architecture boundary tests | ADR-017, `crates/architecture-tests` |
| Problem-code error surface (RFC 9457) | `crates/core/src/error_registry.rs`, `crates/api/src/problems` (ADR-031) |
