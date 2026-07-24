# ADR-018: OIDC JWT Validation & Dev-Auth Toggle

**Status**: Accepted
**Date**: 2026-07-20
**Author**: Tobias Rademacher (@tradem)
**Supersedes**: —
**Related**: ADR-010 (IdP selection: Logto-first, IdP-agnostic RSA/JWKS
  validation), ADR-017 (Architecture Testing Strategy — `core` must stay free
  of HTTP/OIDC dependencies), ADR-001 (Hexagonal Architecture)
**Source change**: `openspec/changes/add-oidc-auth-and-membership`

---

## Context

The `add-oidc-auth-and-membership` change introduces OIDC bearer-token
authentication for the API (see `crates/api/src/auth/`). Two implementation
decisions were left as "optional formalization" in the change's `design.md`
(the JWT-validation-crate decision, **D1**, and the dev-mode auth toggle,
resolution of **Open Question 3**)
and need to be recorded as architecture decisions so they are not lost when the
change is archived.

The forces at play:

- **IdP-agnosticism (ADR-010).** The deployment chooses the IdP (Logto at dev;
  production IdP governed by ADR-010). The backend must validate *standard OIDC
  JWTs* and must **not** couple to any IdP SDK, so that switching IdPs is a
  configuration-only change (`OIDC_ISS` + `OIDC_JWKS_URL`).
- **Pure `core` (ADR-017).** `crates/core` may not depend on HTTP/OIDC crates.
  JWKS discovery and token verification therefore live in `crates/api`, behind
  a trait so tests can inject a static key set.
- **Local dev & test ergonomics.** Developers and tests must run the API
  without a real IdP, but the bypass must be **structurally unreachable in
  production**.

## Decision

### JWT validation — `jsonwebtoken` + async JWKS (Decision D5)

- Use the [`jsonwebtoken`](https://crates.io/crates/jsonwebtoken) crate with
  algorithm **RS256** (standard asymmetric OIDC signing).
- `iss` / `aud` / `exp` / **signature** are enforced by `jsonwebtoken::Validation`
  + `jsonwebtoken::decode::<Claims>`, reading the expected claims straight from
  the token.
- The decoding key is resolved by the token's `kid` (JWK key id) from an
  injectable `JwksProvider` trait defined in `crates/api/src/auth/jwks.rs`.
- **Production implementation — `CachingJwksProvider`:**
  - Fetches the IdP JWKS document over HTTP via `reqwest::Client`.
  - Caches the resolved `(kid -> DecodingKey)` map for a **1-hour TTL**, served
    from cache while fresh.
  - Refreshes on cache miss, expiry, or a validation failure (key rotation is
    handled automatically).
  - Accepts **RSA signing** keys only (skips non-RSA and `use: "enc"` keys) and
    normalizes JWK `n`/`e` from base64url to standard base64.
- **Test / dev implementation — `StaticJwksProvider`:** a fixed key set, used
  by unit/integration tests and the dev-mode dummy verifier (no network).
- The verified `sub` claim is wrapped as an opaque `UserId` in `core`
  (ADR-010); `core` never decodes or stores further identity attributes.

### Dev-mode auth toggle — env-gated, production-unreachable (Decision D6)

- `AuthState::from_env_or_dev()` builds the runtime auth state:
  - **If `OIDC_ISS`, `OIDC_AUDIENCE`, and `OIDC_JWKS_URL` are all set** →
    production mode: real token verification against the `CachingJwksProvider`.
  - **Else if `DEV_AUTH_SUB` is set** (and `OIDC_ISS` is absent) → **dev mode**:
    a dummy `CurrentUser` (`sub = DEV_AUTH_SUB`, optional `email` from
    `DEV_AUTH_EMAIL`) is injected and token verification is **skipped**.
  - **Else** → startup error (neither real OIDC config nor a dev subject).
- `main.rs` only ever enters dev mode when `OIDC_ISS` is absent **and**
  `DEV_AUTH_SUB` is present. Production deployments always set `OIDC_ISS`, so
  the dev bypass is **structurally unreachable in production**.
- `auth_middleware` short-circuits when the state carries a `dev_override`
  (inserts the dummy user and returns immediately); otherwise it runs the full
  verify path.
- The toggle is explicitly documented as **dev/test only — never for
  production** (see `AGENTS.md` §6 and the `CurrentUser::dummy*` helpers).

### Fail-closed posture

- Missing IdP config *and* no `DEV_AUTH_SUB` ⇒ startup failure (no silent
  auth-less mode).
- JWKS fetch/parse failure ⇒ `503` (IdP/backend fault, not the client's).
- Unverifiable / expired / wrong-audience token ⇒ `401`.

## Alternatives Considered

- **IdP vendor SDK (e.g., Logto/Auth0 client):** would violate the IdP-agnostic
  goal of ADR-010 and couple the backend to a vendor. Rejected.
- **Symmetric HS256 shared secret:** OIDC uses asymmetric RSA signing; HS256
  would require distributing a shared secret and is not how IdP-issued JWTs are
  signed. Rejected.
- **No dev toggle (always require a real IdP):** makes local dev and the test
  suite depend on a live IdP. The env-gated, production-unreachable toggle
  removes that friction without introducing a production risk surface.
- **Static/in-memory JWKS in production:** would not pick up IdP key rotation.
  `CachingJwksProvider` with TTL + on-failure refresh handles rotation.

## Consequences

**Positive:**

- **IdP-agnostic:** switching IdPs is configuration-only (`OIDC_ISS` +
  `OIDC_JWKS_URL`); no code change (ADR-010).
- **`core` stays pure** (ADR-017): all OIDC/HTTP logic is confined to `api`
  behind the `JwksProvider` trait.
- **Dev/test ergonomics** without a real IdP, via an env-gated bypass that
  production can never reach.
- **Fail-closed** by construction (`503` / `401` / startup error); no silent
  unauthenticated path.
- `jsonwebtoken` is a widely used, actively maintained crate; key rotation is
  handled by the caching provider.

**Negative:**

- A dev-mode bypass exists at all. It is mitigated by being unreachable in
  production (requires `OIDC_ISS` absent) and documented as never-for-prod.
- `api` now depends on an HTTP client (`reqwest`) for JWKS fetching.

**Neutral:**

- Relies on the IdP publishing an RS256 RSA JWKS document — true for all
  standard OIDC providers, including Logto.
