<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: kimi-k3 (neuralwatt) -->

# Proposal: Unified RFC 9457 Problem-Detail Error Surface with Stable Codes and Server-Side i18n

## Why

The API's error contract is currently underspecified and leaks internals. Every
error path returns a bespoke `{ "message": "…" }` JSON body whose string is a
raw, English, compile-time-interpolated Rust error (`DomainError::to_string()`,
auth middleware `serde_json::json!`, Axum plain-text rejections). That has four
concrete defects:

1. **No machine-readable identity.** Clients (web, Flutter, Slint) cannot
   branch on *what* went wrong — only on the coarse HTTP status. Business
   logic like "offer to reload because of a version conflict" is impossible
   without parsing human prose.
2. **Not localizable.** Messages are built deep in the domain layer with
   interpolated entity IDs long before the HTTP layer sees them, so
   `Accept-Language` translation is structurally impossible. The product
   explicitly ships to a de+en audience first, with fr/es/pt/pl/tr/it/uk
   planned — several of which have CLDR plural/gender rules that plain
   string templates cannot express.
3. **Privacy/credibility risk.** Messages embed internal UUIDv7s and opaque
   join data (`AlreadyAssigned { assigned_to }`) without any policy about
   which identifiers a caller may learn. A 500 with a sqlx error text is
   one panic away.
4. **No debugging correlation.** OpenTelemetry traces exist (archived
   `add-opentelemetry-tracing`) but the `trace_id` never reaches the client,
   so support cannot connect a user-visible failure to server telemetry.

This is architectural, not cosmetic: it decides the error *contract* for every
future client, so it must be settled before the client surface hardens and
before the first external integrator depends on the current ad-hoc shape.

## What Changes

- **BREAKING**: All error responses (domain errors, auth middleware rejections,
  Axum extractor/rejection failures, unknown-route 404s, payload-limit
  rejections, panic fallback) switch from `{ "message": string }` / plain text
  to `application/problem+json` documents per RFC 9457.
- Introduce a **stable, versioned machine-code registry** using
  `{context}.{reason}` kebab-case codes (e.g. `scene.already-scheduled`,
  `costume.already-assigned`, `concurrency.version-mismatch`,
  `http.bad-json-body`, `auth.missing-active-block`). Codes are never reused
  and only removed with an API major bump (per ADR-021).
- Introduce **typed, whitelisted extensions** per code following an S0/S1/S2
  privacy classification (request-supplied IDs always; in-scope aggregate IDs
  only after the handler's authz gate has passed; person identifiers and
  cross-tenant data never).
- Add a `trace_id` extension carrying the W3C trace id of the request span
  (RFC 9457 extension slot, in place of a dereferencable `instance` URI).
- Localize the human-readable `detail` server-side via **Fluent** bundles
  (`de` default, `en` second), negotiated with a q-value-aware
  `Accept-Language` extractor (`uk → de → en`-style fallback chains). `title`
  stays constant English per code.
- Restructure `DomainError` from string-carrying to **structured variants**
  (resource kind + typed IDs) so codes and parameters survive to the HTTP
  boundary; collapse the ~78 `map_err` call sites into a single
  `IntoResponse` implementation.
- Tighten status semantics: 400 reserved for malformed documents/headers,
  **422 Unprocessable Entity for domain validation failures**
  (**BREAKING** for any client branching on the old 400), 401/403/404/409/503
  retained with a documented existence-oracle policy.
- Restriction into the OpenAPI spec: one `ProblemDetails` schema, registered
  `application/problem+json` content type, documented code registry.

## Capabilities

### New Capabilities
- `http-error-surface`: The RFC 9457 problem-detail contract — body shape,
  content type, code registry and naming, per-code extension whitelists,
  S0/S1/S2 privacy classification, status-code semantics (400 vs 422, 401 vs
  403, existence-oracle policy), `trace_id` extension, and coverage of all
  error sources including framework rejections and the panic fallback.
- `error-localization`: Server-side localization of the `detail` field —
  Fluent message bundles, `Accept-Language` q-value negotiation, fallback
  chain, the code→message-key 1:1 mapping rule, bundle file layout ready for
  a future translation-platform import, and bundle coverage linting (every
  code must have de+en messages).

### Modified Capabilities
(none — existing specs such as `oidc-authentication` only constrain status
codes, which this change preserves; the error *body* was previously
unspecified and is now specified by the new capabilities above.)

## Impact

- **Code**: `crates/core/src/error.rs` and all 12 `From<*Error> for DomainError`
  implementations restructured (string → structured); `crates/api` gains a
  problem-detail module (builder, code registry, Fluent loader,
  `Accept-Language` extractor, panic/rejection catch-all); ~78 `map_err`
  call sites in `crates/api/src/handlers/mod.rs` collapse to `?`;
  auth middleware `AuthError` adopts the shared problem builder.
- **Contract/OpenAPI**: `ErrorResponse` schema replaced by `ProblemDetails`;
  `application/problem+json` registered; code registry documented at
  `docs/errors/` (dereferencable `type` anchors).
- **Dependencies**: `fluent` + `fluent-bundle` (+ `unic-langid`, and an
  `accept-language` parser or equivalent) added to `crates/api`; `core`
  stays dependency-clean (codes are plain `&'static str` constants).
- **Clients**: **BREAKING** — all frontends/clients must switch from
  `message` parsing to `code`-based handling; `detail` is a display
  convenience only.
- **CI/guardrails**: new golden-file tests (serialized problem JSON per code,
  so extension diffs are visible in review), bundle-coverage lint (every
  registry code has messages in all active locales), and an ast-grep rule in
  `architecture-checks.yml` forbidding person identifiers (`sub`, `email`)
  in problem-extension builders (S2 enforcement).
- **ADR**: ADR-031 records the decisions (shape, codes, i18n, privacy tiers,
  oracle policy, deprecation rule).
- **Security posture**: net positive — 500s become static localized text with
  `trace_id`; identity data never appears in extensions; the oracle policy is
  written down for the first time.
