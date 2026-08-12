<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: kimi-k3 (neuralwatt) -->

# Tasks: Problem-Detail Error Surface

## 1. Tranche 1 — Problem envelope & unified catch-all

- [x] 1.1 Add `ProblemDetails` type + shared problem builder module in `crates/api` (envelope members, `application/problem+json` content type, `trace_id` capture from the otel span)
- [x] 1.2 Create the code-registry skeleton in `crates/core` (registry entry type: code, status, title, allowed extension fields) with framework codes (`http.*`, `auth.*`, `concurrency.version-mismatch`)
- [x] 1.3 Implement `IntoResponse for DomainError` via the registry (temporary: generic per-variant codes where structure isn't ported yet) and collapse the `map_err` call sites in handlers to `?` propagation
- [x] 1.4 Route `AuthError` middleware rejections through the problem builder (`auth.unauthenticated`, `auth.missing-active-block`, `auth.invalid-active-block`, `auth.idp-unavailable`)
- [x] 1.5 Add rejection handlers for Axum extractor failures (`http.bad-json-body`, `http.bad-path-param`, `http.bad-query-param`), body-size limit (`http.payload-too-large`, 413), unknown routes (`http.route-not-found`, 404)
- [x] 1.6 Add panic catch-all returning `http.internal-error` with static localized-safe text and correct `trace_id`
- [x] 1.7 Switch domain validation failures from 400 to 422 and document the breaking change in the OpenAPI spec/changelog
- [x] 1.8 Update the OpenAPI spec: `ProblemDetails` schema, `application/problem+json` for all error responses, registry-woven docs
- [x] 1.9 Integration test: one HTTP-layer test per error source asserting envelope, content-type, `code`, and `trace_id` presence

## 2. Tranche 2 — Structured domain errors & code registry

- [x] 2.1 Restructure `DomainError` variants from string-carrying to structured (resource kinds, typed IDs) in `crates/core`
- [x] 2.2 Port all `From<*Error> for DomainError` impls (12 modules) to the structured form, deleting interpolated `format!` messages
- [x] 2.3 Register every domain code (`{context}.{reason}`) with status, constant English title, and declared S0/S1 extension fields; derive `type` URI from code
- [x] 2.4 Populate extension whitelist per code; build extensions only from declared fields so undeclared fields fail compilation
- [x] 2.5 Classify every extension field S0/S1 in the registry and add the documented S2 ban (no person identifiers, no cross-tenant data)
- [x] 2.6 Golden-file serialization tests: snapshot the problem JSON per code; CI fails on any extension/envelope diff
- [x] 2.7 Add ast-grep rule to `architecture-checks.yml` + pre-commit hook forbidding `sub`/`email` field references in problem-builder code (S2 enforcement)
- [x] 2.8 Verify S1 gating: audit every S1-carrying code that its handler runs the authorization gate before the failure can occur (AUTHZ-GATE comment present)

## 3. Tranche 3 — Server-side i18n

- [x] 3.1 Add `fluent`, `fluent-bundle`, `unic-langid`, `accept-language` to `crates/api` (and `cargo deny` review); core stays dependency-free
- [x] 3.2 Lay out `crates/api/locales/de/errors.ftl` and `crates/api/locales/en/errors.ftl` using standard Fluent syntax only (Pontoon/Weblate-importable)
- [x] 3.3 Implement the `Accept-Language` extractor with q-value parsing, supported-set matching, and fallback chain `requested… → de → en` (absent/garbage → `de`)
- [x] 3.4 Wire the problem builder to render `detail` from the negotiated locale bundle using declared extension values as Fluent arguments (interpolation, never `format!`)
- [x] 3.5 Add bundle-coverage lint (CI): every registry code has messages in all active locales; every bundle key maps to an existing (or deprecated) registry code
- [x] 3.6 Write `de` + `en` messages for every registered code, using `select` expressions wherever plural/gender applies (pre-validating the pl/uk readiness)
- [x] 3.7 HTTP integration tests: same failure under `de`, `en`, q-valued header, missing header (→ `de`), and unsupported locale (→ fallback chain)

## 4. Documentation & governance

- [ ] 4.1 Write `docs/errors/` documentation pages per code (dereferencable `type` anchors) from the registry
- [ ] 4.2 Finalize ADR-031 (status → Accepted after Tranche 1 merges), add existence-oracle policy and code depreciation rule text
- [ ] 4.3 Update `AGENTS.md` error-handling section to point at the problem builder + registry instead of `map_err`
- [ ] 4.4 Client migration note: one page describing the switch from `message` parsing to `code`-based handling (web/Flutter/Slint)
- [ ] 4.5 `openspec validate add-problem-details-error-surface --strict` green; CI architecture checks green
