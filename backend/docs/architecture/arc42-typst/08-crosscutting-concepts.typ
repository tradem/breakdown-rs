// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: kimi-k3 (neuralwatt)
// Co-authored-by: ox-alpha-free (opencode-go)
// Co-authored-by: gemini-4-carbon (google)

#import "template.typ": *


= Crosscutting Concepts

== HTTP Error Contract (RFC 9457)

#adr-ref(num: "031", slug: "http-error-surface", title: "HTTP Error Surface")

- Every HTTP failure returns `application/problem+json` from one central builder
  (`crates/api/src/problems`).
- `crates/core/src/error_registry.rs` declares all problem codes through the
  `problem_codes!` macro. CI rejects standalone `ProblemCode` constants.
- Extension fields use sensitivity tiers `S0` (public) and `S1` (after
  `AUTHZ-GATE`). Tier `S2` (PII such as OIDC `sub` or email) never enters
  error responses.
- The server localizes `detail` with Fluent (`de` default). The Flutter client
  branches on the stable `code` field and renders its own ARB copy.

== Authentication and Scoped Authorization

Full control pointers live in
#link("../../security/security-architecture.md")[`backend/docs/security/security-architecture.md`].

=== Trust Boundaries and Deny-by-Default Routing

- *TB1 (`auth_middleware`)*: checks RS256 OIDC JWT signatures, `iss`, `aud`, and
  `exp` against cached JWKS keys (3600 s TTL, refreshed on miss or verification
  failure). Dev authentication (`DEV_AUTH_SUB`) activates only when OIDC
  variables (`OIDC_ISS`) are unset (#adr-ref(num: "018", slug: "oidc-jwt-validation-and-dev-auth-toggle", title: "OIDC Validation")).
- *Authorization enforcement toggle*: `AuthorizationState` evaluates its own
  condition (`AUTHZ_ENFORCE`, defaulting off when `DEV_AUTH_SUB` is set).
  Deployments with `OIDC_ISS` must never leave `DEV_AUTH_SUB` set (issue `#935`).
- *TB2 (`authorize_middleware`)*: forwards `/v1/health`, `/health`, and paths
  starting with `/swagger-ui` or `/api-docs` directly. For all other paths,
  `requirement_for()` classifies access and defaults unlisted paths to
  `Requirement::BlockMember`.
- *Fail-closed isolation*: `authorize_middleware` runs policy evaluation in a
  spawned task so a panic maps to `Deny`. With enforcement on, this returns
  `403`, never `500`. In log-only mode (`AUTHZ_ENFORCE=false`), the middleware
  logs the denial and forwards the request.

=== Effective Role Scopes and Handler Gates

- *Block and project scopes*: `effective_costume_role_in_season` checks an
  active block-scoped role first (`projection_membership`) and falls back to an
  active project-scoped costume role (`projection_project_membership`). Manual
  report archival stays block-only by design.
- *Project-wide piece photos*: piece photo handlers check
  `authorize_piece_in_project` so wardrobe staff can manage carried-over pieces
  across seasons of the same project.
- *Owner-scoped Vault bindings*: `/v1/settings/{id}*` and AI config key links
  check both `has_active_credential_role` and `owner == caller` (#adr-ref(num: "028", slug: "settings-aggregates-access-control", title: "Settings Access Control")).
- *Explicit `AUTHZ-GATE` markers*: every `Requirement::Authenticated` handler
  that accesses scoped data calls `membership_gate` and carries an
  `// AUTHZ-GATE:` comment. The Flutter client checks `currentMembershipProvider`
  for actions and reads global capabilities from `GET /v1/me/capabilities`.

== Cryptography and GDPR Right to Erasure

- *Encryption in transit and at rest*: `step-ca` secures internal links, and
  Caddy secures public HTTPS (#adr-ref(num: "024", slug: "database-encryption-in-transit", title: "Encryption in Transit")).
  The Flutter client pins its flavor Root CA (`withTrustedRoots: false`), and
  LUKS2 encrypts VPS volumes (#adr-ref(num: "023", slug: "database-encryption-at-rest", title: "Encryption at Rest"),
  #adr-ref(num: "032", slug: "flutter-client-tls-pinning-rotation", title: "Client TLS Pinning")).
- *GDPR Article 17 in an append-only log* (#adr-ref(num: "029", slug: "gdpr-right-to-erasure-append-only-log", title: "GDPR Right to Erasure")):
  SierraDB event streams never rewrite history. Instead, the system destroys
  per-credential Vault Transit DEKs (crypto-shredding), scrubs personal fields
  in mutable PostgreSQL projections, and keeps raw PII out of error payloads.

== Event Sourcing, Projectors, and Error Hygiene

#table(
  columns: 3,
  table.header([Error Class], [Typical Cause], [System Action]),
  [Transient (`ServiceUnavailable`)], [Network blip, Garage or DB restart], [Retry with backoff (`retry_transient`) or hold behind circuit breaker],
  [Permanent (`ValidationError` / SQL 22, 23)], [Invalid payload or constraint conflict], [Skip known uniqueness race in savepoint (`#404`) or record in `projection_dead_letter` (`#37`) and advance checkpoint],
  [Not found (`NotFound`)], [Object already absent on delete], [Treat as idempotent success in delete and GC flows],
)

#important[
  Production code never discards fallible results. Rust enforces `discard-result`
  with `ast-grep`, and Flutter enforces `discard_result` and
  `no_throw_in_data_domain` with `breakdown_lints`.
]

== Time, Identity, Localization, and Observability

- *Identifiers and sort order*: all entities use `UUIDv7` (#adr-ref(num: "004", slug: "use-uuidv7", title: "Use UUIDv7")).
  Ordered lists use `LexicalSortKey` for fractional insertion without renumbering.
- *Timestamps*: `jiff` and `infra::db_time` handle all instants and civil dates
  while preserving byte-identical RFC 3339 event serialization (#adr-ref(num: "040", slug: "jiff-replaces-chrono", title: "jiff Replaces chrono")).
- *Localization*: the backend uses Fluent (`errors.ftl`), and Typst reports
  format for `de-DE` (#adr-ref(num: "022", slug: "pdf-reporting-and-archival", title: "PDF Reporting")).
  The Flutter app uses `flutter gen-l10n` ARB catalogs (`de` and `en` with CI
  parity checks, #adr-ref(num: "034", slug: "flutter-app-localization-gen-l10n", title: "Flutter Localization")).
- *Observability*: `tracing` spans instrument HTTP handlers, aggregates, sagas,
  and projectors, with OpenTelemetry OTLP export hooks (#adr-ref(num: "011", slug: "observability-with-opentelemetry", title: "Observability"))
  and operator diagnostics at `GET /v1/ops/projector-health`.

== Verification Pyramids

#table(
  columns: 3,
  table.header([Verification Layer], [Backend (`backend/`)], [Flutter Client (`frontend-flutter/`)]),
  [Static and boundary gates], [`clippy` deny, `cargo-deny`, `rust_arkitect`, `ast-grep`], [`flutter analyze`, `breakdown_lints_runner`, OpenAPI drift check],
  [Unit and property tests], [Deterministic `core` tests + `proptest`], [Pure `core/` + `data/` + `domain/` tests (`Ok` and `Err` branches)],
  [Component / integration], [`axum` auth/contract tests + `testcontainers` Tiers 1–4], [Semantic-finder widget tests + `matchesGoldenFile` goldens],
  [Acceptance / adversarial], [CI `cargo-mutants --in-diff` + nightly `cargo-fuzz`], [On-device `flutter_gherkin` critical flows + `integration_test` + `coverde`],
)
