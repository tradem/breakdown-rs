## Context

The backend today is fully open: every Axum handler executes without any notion of a caller, and `core`'s four Bounded Contexts (`scene`, `character`, `costume`, `calculation`) have no concept of *ownership*, *membership*, or *auditing who acted*. The only existing tenancy seam is `ProjectId` (`crates/core/src/shared.rs`), an opaque UUIDv7 value passed into each `Create*` command by hand — there is no `Project` aggregate that records who created or owns a project.

ADR-010 (*Authentication with OpenID Connect*) constrains the solution space decisively:

- **Authentication is externalized.** The backend never handles passwords, MFA, registration, or session storage. It only validates cryptographically signed JWTs issued by an OIDC provider (Logto Cloud first; Zitadel migration later).
- **No IdP-specific SDK in the backend.** Switching IdPs is a configuration change (`iss` + JWKS URL).
- **Multi-tenancy exists at the IdP level** via Logto Organizations.

Stakeholder input (still pending, see Open Questions) confirms the direction: roles are *production-scoped* (`Kostümbildner*in`, `Garderobier*in`) — a person's role changes per production, so roles cannot live as IdP-global organization roles. The `Project` aggregate itself is deferred pending a separate stakeholder-aligned change; meanwhile `ProjectId` remains opaque exactly as today.

```
   Logto/Zitadel (IdP)              Rust backend
   ─────────────────                ──────────────────────────────────
   • account lifecycle              • validate signed JWT (api layer)
   • passwords, MFA, SSO            • extract CurrentUser { sub, ... }
   • Organizations (tenancy)        • authorize per-project (api layer)
   • global technical admins        • core/membership references sub
                                    as opaque UserId (value type)
   ─ DOES NOT live in core ─        ─ core stays pure domain ─
```

## Goals / Non-Goals

**Goals:**
- Implement the ADR-010 OIDC seam: JWT validation + `CurrentUser` extraction in `crates/api`, with no IdP-specific SDK coupling.
- Introduce a `membership` Bounded Context in `crates/core` modeling project-scoped membership and roles, following the established `aggregate/commands/events/error/ports/views` schema.
- Provide an authorization policy in `crates/api` that consults the membership read model before write commands and project-scoped reads.
- Keep `core` free of any identity/account lifecycle concerns. `UserId` is an opaque value type referencing the IdP `sub`.
- Path the existing commands for audit via `kameo_es` command metadata (the `Metadata` type already in use), not by polluting command payloads.

**Non-Goals:**
- The `Project` aggregate (name, dates, status, archived flag). It is its own future, stakeholder-driven change. `ProjectId` stays opaque.
- Account lifecycle: registration, email verification, password reset, MFA, social login — all IdP territory.
- IdP selection / migration tooling. ADR-010 says Logto first; this change assumes Logto-compatible OIDC and does not build migration tooling.
- A full RBAC/ABAC framework. Authorization is a thin, project-scoped policy in the API layer.
- Finalizing the complete role set. Initial roles `Kostümbildner*in` and `Garderobier*in` are modeled; the role enum is open for extension pending stakeholder confirmation.
- Row-level multi-tenancy across theaters. Tenancy at the IdP `Organization` level is acknowledged but not enforced inside `core` in this change.

## Decisions

### 1. Authentication: validate standard OIDC JWTs in an Axum middleware
**Decision.** A `tower`/Axum middleware fetches and caches the IdP JWKS, verifies token signature, `iss`, `aud`, and `exp`, and inserts a `CurrentUser { sub, email, ... }` into request extensions. Handlers obtain it via an `axum::extract::FromRequestParts` extractor.
**Rationale.** ADR-010 mandates backend-only-JWT-validation with no IdP SDK. A middleware + extractor matches Axum idioms and keeps handlers testable with a fake `CurrentUser`.
**Alternatives considered.** (a) `tower-http`'s auth layers — too generic, would reimplement JWKS caching anyway. (b) `oxide-auth` — an authorization *server*, not what we need; we are a *resource server*. (c) Per-handler validation — scatters logic, easy to forget a handler.

### 2. `UserId` as an opaque core value type, not an aggregate
**Decision.** `crates/core/src/shared.rs` gains `UserId(String)` (the OIDC `sub` claim), mirroring `ProjectId`'s pattern. `core` never decodes, validates, or stores identity attributes — it only references `UserId` as a foreign identifier.
**Rationale.** ADR-010 keeps identity out of `core`. Modeling `User` as an aggregate would pull account lifecycle (and security-critical hashing) into the event-sourced domain, conflicting with `core`'s pure-domain stance and complicating `cargo mutants`/security-audit boundaries.
**Alternatives considered.** (a) A separate `crates/identity` crate for an account aggregate — rejected; ADR-010 externalizes accounts entirely, so there is no account aggregate to host. (b) Pass the raw `sub: String` everywhere — rejected; a wrapper gives type safety and consistent serialization with the rest of `shared.rs`.

### 3. `membership` as its own Bounded Context, separate from a future `project` context
**Decision.** Add `crates/core/src/membership/` with aggregate `ProjectMembership`, scoped per `ProjectId`, holding a `{ user_id: UserId -> role: Role }` map. The aggregate does not own project metadata — only membership.
**Rationale.** Two narrow aggregates (`Project` later, `Membership` now) keep command streams focused and avoid a bloated `Project` aggregate where every membership change competes with every project-metadata edit for the same stream lock. This mirrors how `scene`/`character`/`costume`/`calculation` already coordinate loosely via `ProjectId` rather than nesting.
**Alternatives considered.** (a) Fold membership into the future `Project` aggregate — rejected on granularity grounds above. (b) Defer membership until `Project` exists — rejected; the authorization seam is needed before exposing the API to real users, and `ProjectId` is already available without a `Project` aggregate.

### 4. Roles are domain-local, modeled as an open `enum`
**Decision.** `Role` is an `enum` in `crates/core/src/membership`, initially `Kostümbildner` and `Garderobier`, designed so new variants are additive (backwards-compatible deserialization).
**Rationale.** Roles are production-scoped — a person is `Kostümbildner*in` in one project and `Garderobier*in` in another, so they cannot be IdP-global organization roles. An `enum` gives compile-time exhaustiveness for authorization matching. Extensibility is acceptable as long as additions are purely additive.
**Alternatives considered.** (a) Store roles as IdP Organization roles — rejected; production-scoped roles need per-project assignment. (b) `String`/free-form roles — rejected; loses exhaustiveness and weakens the authorization policy. (c) A separate `Role` value object with permission sets — premature; deferred until the role set and permission matrix are stakeholder-confirmed.

### 5. Authorization lives in `crates/api`, not in `core`
**Decision.** A policy module in `crates/api` queries the membership read model before dispatching write commands (and before returning project-scoped reads) and translates a deny decision into an HTTP 403. `core` aggregates do not receive the caller and do not enforce authorization.
**Rationale.** Authorization is an application concern depending on the *read model* (projection) state, which `core` deliberately cannot see (CQRS read/write separation). Putting it in `core` would force the domain to read its own projections and couple write-side to read-side.
**Alternatives considered.** (a) Inject `CurrentUser` into every command and have aggregates self-authorize — rejected; violates the CQRS read/write split and pulls projections into aggregates. (b) A dedicated `crates/authz` crate — deferred; currently a thin policy fits in `crates/api`.

### 6. Audit via `kameo_es` metadata, not command payload
**Decision.** The acting `UserId` is attached as `kameo_es` command metadata for the write side, allowing event-stream audit ("who emitted this event") without changing the command's domain payload. Existing commands (`CreateScene`, `UpdateCostumeNotes`, …) keep their current signatures.
**Rationale.** The acting user is rarely a *domain* concern of `scene`/`costume`/etc.; it is an audit/observability concern. Metadata preserves clean command payloads and avoids retroactive signature churn across all handlers. Where the actor *is* a domain concern (e.g. a future "only a `Kostümbildner` may finalize a calculation"), that specific command will carry the actor in its payload explicitly — but that is decided per-command, not blanket.
**Alternatives considered.** (a) Add `actor: UserId` to every command payload — rejected; pollutes unrelated commands and bloats event payloads. (b) No audit at all — rejected; multi-user collaboration requires an audit trail.

## Risks / Trade-offs

- [IdP availability is a hard runtime dependency] → If Logto Cloud is down, no request can authenticate. Mitigation: short token TTLs + observability; the middleware returns 503 on JWKS fetch failure rather than 401, so the failure mode is honest. A locally cacheable JWKS reduces blast radius.
- [Local dev friction without a local IdP] → dev compose currently has no IdP. Mitigation: support a "dev mode" accepting a fixed dummy `CurrentUser` behind a feature flag/env var (never enabled in prod), so unit/integration tests stay deterministic. Documented in `AGENTS.md` at implementation time.
- [Membership projector idempotency under redelivery] → same projector-redelivery concern as the existing four projectors. Mitigation: reuse the established idempotency pattern from ADR-016 / `projector-supervision`; add a Tier-4 redelivery test mirroring the existing ones.
- [Role set is not yet stakeholder-confirmed] → adding a role later is additive if the enum stays open, but removing one is a breaking change. Mitigation: only commit `Kostümbildner` + `Garderobier` as the v1 set in the spec; further roles wait for stakeholder sign-off (see Open Questions).
- [Tenancy (`Organization`) inside `core` is deferred] → the membership model is per-`ProjectId` and does not yet enforce that a user belongs to the theater owning the project. Mitigation: explicit Non-Goal; the IdP organization check happens upstream at login, and per-theater isolation inside the domain is a follow-up change once `Project`↔`Organization` is modeled.

## Migration Plan

- Pure addition — no breaking API change unless required by the decision to gate previously-open endpoints. The migration is staged:
  1. Ship the OIDC middleware + `CurrentUser` extractor behind a feature flag, with authorization in "log-only" mode (allowing all requests but recording the actor), so existing flows are unaffected.
  2. Add the `membership` BC + projector + projection migration.
  3. Flip authorization from "log-only" to "enforce" for project-scoped endpoints once integration tests cover the policy.
- Rollback: keep the feature flag in step 1/3 so enforcement can be disabled at runtime if a policy regression slips through.

## Open Questions

1. **Final role set.** Beyond `Kostümbildner*in` and `Garderobier*in`, are roles like `Regie`, `Maske`, `Produktionsleitung` expected for v1? (Stakeholder.) Determines whether the spec is committed with two roles or a larger set.
2. **Theater-as-tenancy.** Is a "theater" a Logto `Organization` that *contains* multiple projects, or is each project independently accessible? (Stakeholder / product.) Affects whether `Project` (future change) needs an `organization_id` and whether the membership model needs cross-theater isolation in v1.
3. **Dev-time IdP.** Local dev without Logto Cloud: dummy `CurrentUser` via feature flag, self-hosted Logto container in dev compose, or a tiny mocked JWKS server? (Technical — resolves at design-into-implementation.)
4. **JWT validation crate.** `jsonwebtoken` (manual JWKS caching) vs. a higher-level OIDC resource-server crate. (Technical — resolves at design-into-implementation.)
5. **Audit storage.** Is `kameo_es` metadata sufficient for audit, or do stakeholders need a dedicated, queryable audit projection? (Stakeholder + technical.)
