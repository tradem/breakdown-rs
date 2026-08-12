<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: kimi-k3 (neuralwatt) -->

# ADR-031: HTTP Error Surface — RFC 9457 Problem Details, Stable Codes, Server-Side i18n

**Status**: Proposed
**Date**: 2026-08-12
**Author**: Tobias Rademacher (@tradem); Co-authored-by: kimi-k3 (neuralwatt)
**Related**: ADR-012 (error handling types), ADR-021 (API versioning), ADR-030 (bounded contexts)
**Source change**: `openspec/changes/add-problem-details-error-surface`

---

## Context

The API returned ad-hoc error bodies: `{ "message": "…" }` JSON from handlers
and auth middleware, and plain text from framework rejections. Messages were
English, built deep in the domain layer with interpolated entity IDs
(`DomainError::to_string()`), so the responses were:

- not machine-actionable for clients (web, Flutter, Slint), which could only
  branch on coarse HTTP statuses and had to parse human prose otherwise;
- not localizable, although the product ships de+en now and targets
  fr/es/pt/pl/tr/it/uk later (several with non-trivial CLDR plural rules);
- without debugging correlation — the otel `trace_id` never reached clients;
- without a privacy policy for which identifiers an error may reveal;
- inconsistent about statuses (e.g. 400 both for malformed JSON and for
  domain validation failures).

Constraints: `core` must stay free of HTTP/i18n dependencies (ADR-017); the
handler-internal `AUTHZ-GATE` pattern already guarantees scope checks before
domain failures surface; clients are being built in parallel, so the contract
had to be fixed now (cheapest breaking-change window).

## Decision

1. **Envelope.** Every error response (≥ 400) from every source — domain
   errors, auth middleware, extractor/rejection failures, unknown routes,
   payload limits, panic fallback — is a single shared
   `application/problem+json` (RFC 9457) document built by one problem
   builder. Extensions per RFC 9457 §3 are used deliberately:
   - `code` — the stable machine identity (see 2);
   - `trace_id` — the W3C trace id of the request span;
   - per-code typed extension fields (see 4).
   `title` is a constant English string per code; only `detail` is localized.
   The dereferencable `instance` URI is consciously **not** used (would need a
   problem-instance store); `trace_id` covers the support use case via otel.
2. **Codes.** Every failure gets a stable `{context}.{reason}` code in lower
   kebab-case, e.g. `scene.already-scheduled`,
   `concurrency.version-mismatch`, `http.bad-json-body`,
   `auth.missing-active-block`. Namespaces: per aggregate plus `concurrency.`,
   `http.`, `auth.`. The single registry (in `core`, dependency-free data) is
   the source for the code, the English `title`, the localization key, and the
   dereferencable `type` URI anchor (`{docs-base}/problems/{code}` — derived,
   never stored separately). Published codes are never reused and only removed
   with an API major bump (ADR-021); deprecated codes keep their locale
   messages until removal.
3. **Localization.** `detail` is localized server-side with **Mozilla Fluent**
   (`fluent-bundle`), one bundle per locale at
   `crates/api/locales/<lang>/errors.ftl` (standard Fluent only, so
   Pontoon/Weblate import verbatim). Negotiation parses `Accept-Language`
   including q-values against the supported set with fallback chain
   `requested… → de → en`; absent/invalid header defaults to `de`. Message
   arguments come only from declared extension values via Fluent interpolation
   (never string concatenation). Fluent `select` covers plural/gender so
   adding `pl`/`uk` later is a translator task, not a code change.
4. **Extension privacy classification (S0/S1/S2).** Every extension field of
   every code is declared in the registry and classified:
   - **S0** — client-supplied identifiers (request path/body/query,
     `expected_version`): always allowed.
   - **S1** — aggregate identifiers within the caller's authorized scope,
     e.g. the conflicting shooting day in `scene.already-scheduled`: allowed
     only where the handler's authorization gate ran before the failure
     (membership already grants read access, so nothing new is exposed; these
     IDs are the cheapest traceability lever for support).
   - **S2** — person identifiers (OIDC `sub`, e-mail) and any cross-tenant
     data: never allowed.
   Enforcement is mechanical: undeclared extension fields do not compile to
   the wire; golden-file JSON snapshots per code make every extension diff
   review-visible; an ast-grep rule bans `sub`/`email` references in
   problem-builder code paths.
5. **Status semantics.** 400 is reserved for malformed requests (JSON syntax,
   headers, path params); **422 Unprocessable Entity** signals well-formed but
   domain-invalid documents; 401/403/404/409/413/503 keep their standard
   meanings, with 409 also for optimistic-concurrency
   (`concurrency.version-mismatch`). **Existence-oracle policy**: requests
   from authenticated non-members receive 404 for out-of-scope resources
   (existence is not revealed); members receive truthful statuses because
   membership already implies visibility.
6. **Error type structure.** `DomainError` carries structured data (resource
   kinds, typed IDs) instead of pre-formatted strings; one
   `IntoResponse` implementation at the HTTP boundary replaces per-handler
   status mapping. 500 responses return a static localized `detail` — internal
   error text never leaves the server.

## Consequences

### Positive

- Clients gain a stable, typed branching point (`code` + extensions) usable
  identically from Svelte, Flutter, and Slint.
- de+en user-facing errors ship from the server; the plural-heavy future
  locales need only `.ftl` files and a config entry.
- Support correlation becomes self-service: a screenshot containing
  `code` + `trace_id` maps 1:1 to server telemetry.
- Error mapping consolidates from ~78 `map_err` sites to one implementation;
  handlers just propagate with `?`.
- Privacy stops being convention: S2 data is structurally excluded, S1 changes
  surface in review via golden diffs, and the oracle policy is written down.

### Negative

- **Breaking change** in two steps: body shape (`message` → problem+json) and
  the 400→422 split for domain validation. Mitigated by doing both now, in one
  client migration, before external integrators exist.
- New runtime dependencies in `api` (`fluent-bundle`, `unic-langid`,
  `accept-language`) requiring `cargo deny` review and version pinning.
- Registry, golden tests, bundle lint, and the new ast-grep rule add CI
  surface that must be maintained (the orphan-key lint deliberately tolerates
  deprecated codes, which needs care during the first actual removal).
- Fluent is the committed message format; if icu4x MessageFormat 2 matures
  into the industry standard, a migration means re-authoring bundles (the
  split of registry ↔ bundle layout bounds the blast radius).

## Alternatives Considered

1. **Keep `{message}` and add a parallel `code` field.** Half-measure: leaves
   localization and typed parameters structurally impossible and keeps two
   conventions alive.
2. **Client-side-only i18n (ship codes, no server `detail`).** Rejected:
   forces every client — including thin ones like Slint tooling and
   curl-driven support — to duplicate the message catalogue; server-side
   `detail` remains valuable as the default display text.
3. **Gettext/YAML templates instead of Fluent.** Rejected: inadequate CLDR
   plural/gender ergonomics for Polish/Ukrainian and weaker translator
   tooling.
4. **Dereferencable `instance` URIs with a problem-instance store.** Rejected
   for now (state, retention, GDPR surface) — `trace_id` solves the support
   problem cheaply; `instance` can be added later without breaking clients.
5. **`SCREAMING_SNAKE` codes.** Rejected: kebab-case matches the REST problem
   ecosystem (docs URIs, OAuth-style codes) that clients already inhabit.

## Notes

- Implementation is split into three independently mergeable tranches:
  envelope first (the whole breaking surface), structured registry second,
  Fluent bundles third. Clients migrate once, at tranche 1.
- The S2 ast-grep rule and the bundle-coverage lint join the existing
  `architecture-checks.yml` mechanical guardrails (same pattern as
  `cqrs-boundary`, `discard-result`).
- Golden-file snapshots deliberately only react to *extension* changes —
  the audit-worthy events — keeping rubber-stamp noise low.
- Future locales: add `locales/<lang>/errors.ftl` + one config entry; the
  fallback chain is configuration, not code.
