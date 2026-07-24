# ADR-021: HTTP API Path Versioning & Deprecation Lifecycle

**Status**: Proposed
**Date**: 2026-07-21
**Author**: Tobias Rademacher (@tradem); GLM-5.2 (Zhipu, hosted by neuralwatt)
**Supersedes**: —
**Related**: ADR-006 (introduced v1 endpoints — informal notion this ADR
  formalises), ADR-019 (additive v1→v2 `SeasonCrew` evolution pattern this
  policy matches), ADR-020 (Rust component versioning & release cadence)
**Source change**: tracked in GitHub issue #123

---

## Context

The API is Axum + utoipa (OpenAPI at `/swagger-ui`). ADR-006 informally
labels the OpenAPI document "the persistence-layer v1 endpoints", but the
real routes are *not* under a `/v1` prefix today — "v1" lives only in the doc
title and comments. Multiple first-party clients (Flutter app, Svelte web
app, future TUI/Slint app) update on independent cadences, so a breaking
change to one route breaks clients that have not shipped a new build. The
codebase already evolves additively: ADR-019's `SeasonCrew` v1→v2 migration
adds a new shape beside the old rather than mutating it in place — an
organisation-level convention that an explicit versioning policy must match,
not fight. There is no stated rule relating the `api` crate version
(ADR-020) to an API path version, no deprecation window, no `Sunset` /
`Deprecation` header discipline, and no rule that read-model columns must
stay consumable by older API versions during a deprecation. `cargo-semver-
checks` cannot see HTTP route shapes or `serde` wire formats, so an
additive-looking change that shifts a `serde` default is a silent break that
this policy must classify.

## Decision

### D1: Version-in-URL, prefix `/v{n}`, formalising ADR-006's "v1"

Routes are mounted under a `/v1` path prefix (the existing endpoints move
under `/v1/...` — a one-time additive re-mount, not a behaviour change).
Chosen over header-based and content-negotiation versioning: URL versioning
is greppable in client code, cacheable by intermediaries without Vary
header tricks, matches how the Flutter/Svelte clients already construct base
URLs, and is what ADR-006's "v1" naming already promises clients. The
OpenAPI document's `info.version` field is the API path version (a string
`"v1"`), formalising the existing utoipa label as the source of truth.

### D2: Path version vs. crate version — the rule (they need not be equal)

- **API path version** (`/v{n}`, `info.version`) is bumped **only on a
  breaking HTTP/wire change** to the `api` contract: route method/path
  removal or retyping, request/response field removal or retyping, a
  `serde` default change (additive-but-default-differs is **MAJOR**,
  breaking — D5), status-code semantic change, auth requirement tightening
  on an existing route.
- **`api` crate version** (ADR-020) tracks *product* evolution including
  runtime/security fixes that do not touch the wire contract. A bug fix in a
  handler with no contract change is a crate **PATCH** and bumps the image
  tag; the path version stays `/v1`.
- Rule: **path version major = count of breaking API contract revisions since
  `/v1`; crate version is independent and ≥ path-version major.** A crate
  MINOR/PATCH never forces a new path version. A breaking contract change is
  crate MAJOR + path-version increment, released together.

### D3: Minor/additive change vs. major breaking change

A change is **MINOR** (same path version) iff it is strictly additive at the
wire level: new route, new optional request field, new optional response
field with a `serde` default identical to prior client behaviour, new
optional query param. It is **MAJOR** (new `/v{n+1}` path version) otherwise.
This matches ADR-019's additive v1→v2 pattern: prefer adding a new shape
beside the old over mutating the old in place.

### D4: Multi-client deprecation lifecycle — minimum 8-week window

On shipping `/v{n+1}`:

1. `/v{n}` **must remain served concurrently** with `/v{n+1}` for a minimum
   of **8 weeks** (longer if any first-party client has not cut a release
   against `/v{n+1}` — tracked in the versioning GitHub issue).
2. Every `/v{n}` response to an affected route **must** carry `Deprecation:
   true` and `Sunset: <RFC-8597 date>` headers from the moment `/v{n+1}`
   lands; the Sunset date is the deprecation-window end ≥ 8 weeks out.
3. A changelog entry is mandatory in the same release (ADR-020 `api` release
   notes), naming every moved route and its `/v{n+1}` replacement.
4. At most the two most recent major path versions are served
   concurrently; `/v{n-1}` is removed when `/v{n+1}` ships and `/v{n}`'s
   window has elapsed.

### D5: Additive-but-`serde`-default-differs is breaking (MAJOR)

An added field whose `serde` deserialisation default differs from how an
older client/server pair behaved is **MAJOR** and forces a new path version —
not an additive MINOR. (Example: adding a now-required field, or changing an
absent-field fallback value the old contract implicitly produced.) This rule
overrides any "additive field = MINOR" intuition and is checked by the
contract test in D6.

### D6: Read-model stays consumable by older API versions; contract tests gate it

During a deprecation window, the Postgres read model (ADR-015) must stay
consumable by *both* `/v{n}` and `/v{n+1}`:

- Projection migrations are **strictly additive** within the window: new
  columns nullable with a default; **never rename or drop** a column consumed
  by an open API version until that version's 8-week window has elapsed and
  `/v{n-1}` is off.
- A migration that would drop/rename a column used by an open version is
  **non-goal-deferred** until that version sunsets, then executed as a
  follow-up migration (ADR-020 D4, MAJOR).
- `cargo-semver-checks` cannot see HTTP/`serde` shapes; the gate is a wire-
  contract test in `crates/integration-tests` that records a frozen
  response fixture per `/v{n}` route and asserts the live route still matches
  it byte-for-byte (modulo allowlisted additive fields) on every PR.

## Alternatives Considered

- **Header / `Accept` content-negotiation versioning.** Rejected — opaque to
  intermediaries, hard to grep in client code, forces `Vary` correctness
  everywhere; gains nothing over URL prefixes for a first-party-only client
  set.
- **OpenAPI-only versioning (no real `/v1` prefix).** Rejected — ADR-006's
  "v1" is then a lie: the doc claims a contract the routes don't enforce.
  Clients cannot rely on a prefix that does not exist on the wire.
- **Single concurrent major version (no overlap).** Rejected — Flutter, Svelte,
  and future TUI/Slint clients ship on independent cadences; a hard cutover
  breaks whichever client is slowest. The 8-week floor matches ADR-019's
  already-practiced additive coexistence.
- **Crate-version == path-version (one number).** Rejected — couples
  runtime/security PATCH releases to a wire contract they do not change,
  forcing spurious `/v{n+1}` cuts and violating ADR-020's image-tag stability.

## Consequences

Positive: clients pin a path version and get a documented, ≥8-week window to
migrate, with `Sunset`/`Deprecation` signalling; the contract test in
`crates/integration-tests` makes a silent `serde`-default break a CI failure,
not a production incident; read-model additivity rule keeps old versions
served cheaply. Negative: two major versions must run concurrently for the
window, doubling handler/route surface during overlaps; column drop/rename is
deferred, leaving some read-model debt until sunset; the contract-fixture set
grows with the route surface and must be maintained. Operational impact: new
`/v1` route-prefix re-mount (one-time), `Sunset`/`Deprecation` header
middleware, a wire-contract fixture-replay test extending the ADR-014/016
integration-test crate, and a changelog discipline tied to ADR-020 `api`
releases. Cross-link to ADR-020: every new `/v{n+1}` lands in the same `api`
crate **MAJOR** release that produces a new immutable `api-vX.Y.Z` image tag;
the deprecation window is served by keeping the prior image deployable until
sunset.
