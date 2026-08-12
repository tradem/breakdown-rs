<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: kimi-k3 (neuralwatt) -->

# Design: Problem-Detail Error Surface (RFC 9457 + Codes + Server-i18n)

## Context

Today every error path is a bespoke ad-hoc response:

```
Request ──► AuthError (middleware)              Request ──► Handler ──► map_err()
   │            │  serde_json::json!({message})     │          │  ~78 call sites
   │            ▼                                   │          ▼
   │   {"message":"unauthorized"}                   │   ErrorResponse {message}
   │   status ad hoc                               │   = err.to_string()
   │                                               │   raw english + uuid7 ids
   └──────────────┬─────────────────────────────────┴──────────┘
                  │ Axum rejections: plain text
                  │ unknown route: empty 404
                  ▼
   No code, no params, no trace correlation, not localizable, no privacy policy
```

`DomainError` variants carry pre-formatted strings (`NotFound(format!("Character({id})"))`),
so identity and parameters are already destroyed in `core`. ADR-012 covers the
Rust-internal error *types*; nothing governs the HTTP error *contract*.

Constraints from the hexagonal setup: `core` must stay free of HTTP/i18n
dependencies; the API crate is the only legitimate boundary that can know
locales and status codes; the existing `AUTHZ-GATE` pattern in handlers is the
precondition for safely returning S1-scoped identifiers (see D4).

## Goals / Non-Goals

**Goals:**
- One RFC 9457 `application/problem+json` envelope for every error source.
- Stable `{context}.{reason}` kebab-case codes as the client contract for
  web, Flutter, and Slint (logic branches on `code`, never on text).
- Server-side localized `detail` via Fluent (`de` default, `en`), q-value-aware
  `Accept-Language`, plural/gender-safe for future `fr/es/pt/pl/tr/it/uk`.
- `trace_id` on every problem for support↔otel correlation.
- Privacy policy made mechanical: per-code S0/S1/S2 extension whitelists,
  golden-file tests, S2 lint.
- Status semantics tightened: 400 = malformed, 422 = domain validation
  (breaking, done now while the surface is young), documented oracle policy.

**Non-Goals:**
- Dereferencable problem-instance registry (`/problems/instances/{id}`) with a
  server-side problem store — `trace_id` covers the support case; additively
  later if a support tool needs it.
- Client-side translation bundles — `code`+extensions deliberately *enable*
  client i18n but shipping client bundles is the clients' own change.
- A translation platform (Pontoon/Weblate) — only the directory layout is
  made import-ready; platform choice when locale #3 lands.
- Deprecating/removing any existing code — the registry is being created;
  the deprecation rule applies from publication on.

## Decisions

### D1 — Envelope: RFC 9457 + `code` + `trace_id`, `instance` omitted

Body shape (all members except-extensions per RFC 9457 §3):

```json
{
  "type":      "https://docs.breakdown.example/problems/scene.already-scheduled",
  "title":     "Scene schedule conflict",
  "status":    409,
  "code":      "scene.already-scheduled",
  "detail":    "Die Szene ist bereits auf einem anderen Drehtag eingeplant.",
  "trace_id":  "4bf92f3577b34da6a3ce929d0e0e4736",
  "extensions": { "offending_shooting_day_id": "018g…" }
}
```

- `trace_id` is the otel span's W3C trace id, an RFC-sanctioned extension —
  pragmatic and explicitly allowed; a dereferencable `instance` URI would need
  a problem-instance store (YAGNI).
- `title` is constant English per code (cacheable, spec-stable); only `detail`
  localizes.
- `type` is *derived* from `code` (`{base}/problems/{code}`), never stored
  separately — one registry entry feeds URI, key, and docs anchor.

*Alternatives*: keep `{message}` (rejected: defeats all four drivers);
RFC 9457 with dereferencable `instance` (rejected: needs a store; `trace_id`
solves the same support problem cheaply); Stripe-style `code`+`message`
without RFC 9457 (rejected: reinvents a standard we can just use).

### D2 — Code registry: `{context}.{reason}`, lower kebab-case, in `core`

Codes live in `core` as plain `&'static str` constants next to a typed
registry entry per code (context enum, reason, whitelist of extension fields,
http status, title). `core` stays dependency-free; the registry is data.

Namespaces: per aggregate (`scene.`, `costume.`, `scene-shoot.`, `photo.`,
`membership.`, …), cross-cutting `concurrency.` (optimistic locking), and
framework `http.`/`auth.` (rejections, middleware).

Deprecation rule: published codes are never reused; removal only with an API
major (ADR-021); deprecated codes keep their locale messages until removal
(the orphan-key lint tolerates deprecated entries).

*Alternatives*: `SCREAMING_SNAKE` Rust idiom (rejected: foreign to the REST
ecosystem the clients live in; Zalando/OAuth-adjacent conventions favour
kebab); URNs as codes (rejected: noise for clients; URIs stay in `type`).

### D3 — Structured `DomainError`; one `IntoResponse`; all rejections routed through the problem builder

`DomainError` variants become structured: `NotFound { resource: ResourceKind,
id: Uuid }`, `AlreadyAssigned { costume_id, character_id }`, etc. Each variant
declares its registry entry; strings are built only at the HTTP boundary by
the problem builder. One `impl IntoResponse for DomainError` replaces the ~78
`map_err` sites — handlers collapse to `?` and return `Result<_, ApiError>`.

Coverage beyond domain errors:

| Source                          | Code                       | Status |
|---------------------------------|----------------------------|--------|
| bad JSON / path / query         | `http.bad-json-body` …     | 400    |
| domain validation               | `{agg}.{reason}`           | 422    |
| payload over limit              | `http.payload-too-large`   | 413    |
| no bearer / bad token           | `auth.unauthenticated`     | 401    |
| missing/invalid X-Active-Block  | `auth.*-active-block`      | 400    |
| IdP/JWKS down                   | `auth.idp-unavailable`     | 503    |
| unknown route                   | `http.route-not-found`     | 404    |
| panic fallback                  | `http.internal-error`      | 500 (static detail) |

*Alternatives*: keeping per-handler `map_err` (rejected: the status mapping
duplicated across 78 sites is exactly the inconsistency we're removing);
putting the registry in `api` (rejected: the domain owns the failure
semantics; ownership of codes in `core` keeps `From<*Error>` impls where the
errors originate).

### D4 — Extension privacy: S0/S1/S2 classification, mechanically enforced

- **S0** request-supplied IDs (path/body/query values, `expected_version`):
  always allowed — the client already has them.
- **S1** in-scope aggregate IDs (e.g. the *other* shooting day in a schedule
  conflict): allowed **only** in handlers whose `AUTHZ-GATE` ran before the
  failure. Membership in the scope implies read access to that resource, so
  nothing new leaks. Cross-check: `SeriesId` derived server-side
  (`series_id_for_scene`) is S1-handled: fine after the gate, but never the
  reason an S2 value escapes.
  S1 is exactly the CHEAPEST traceability lever: with `code` +
  `offending_shooting_day_id` a user/support ticket is self-describing.
- **S2** person identifiers (OIDC `sub`, e-mail) and cross-tenant data:
  structurally banned. Membership failures say "already invited", never *who*.

Enforcement: (a) extension fields are declared per code in the registry —
building undeclared extensions doesn't compile; (b) golden-file JSON tests per
code make any registry diff review-visible; (c) an ast-grep rule in
`architecture-checks.yml` rejects `sub`/`email` identifiers in problem-builder
code paths.

*Alternative considered*: "developer comfort" – return every available ID
(rejected: the interesting IDs *are* the in-scope ones; anything beyond
violates the data-minimisation principle the user set as a hard requirement).

### D5 — Localization: Fluent bundles, q-aware negotiation, `de` default

- Crates: `fluent` + `fluent-bundle` + `unic-langid` + `accept-language`
  (q-value parsing) in `api` only.
- Bundles: `crates/api/locales/<lang>/errors.ftl`; standard Fluent syntax only
  (Pontoon/Weblate-importable verbatim).
- Negotiation: parse header → order by q → match supported set → fallback
  chain `requested… → de → en`; absent/garbage header → `de`.
- Key derivation from code: `scene.already-scheduled` →
  `problem-scene-already-scheduled` (mechanical, lint-checked 1:1).
- Only whitelisted extension values become Fluent arguments (D4), rendered
  through Fluent interpolation (escaping handled by the bundle API) — never
  `format!`.

*Alternatives*: `rust-i18n`/gettext YAML (rejected: plural/gender UX is
inferior for `pl`/`uk`, translator tooling weaker); icu4x MessageFormat 2
(rejected as *primary* now: spec and crate maturity; documented as the
migration candidate if MF2 stabilises — bundle layout isolates the choice);
client-only i18n (rejected per decision to ship server `detail` as a
convenience for thin clients like Slint).

### D6 — Status semantics & oracle policy

- 400 malformed / 422 domain-invalid (RFC 9110 §15.5.21; Stripe-style split).
  Done now as a **breaking** change — cheapest moment this API will ever have.
- 401 vs 403 unchanged (`auth.unauthenticated` vs domain `Forbidden`-codes).
- Existence-oracle policy (documented, not changed): requests from
  authenticated non-members receive 404 for resources outside their scope —
  existence is hidden behind "not found" for them; members receive truthful
  404 vs 403/409 because membership already grants visibility. This policy is
  written into ADR-031 so the next reviewer doesn't have to rediscover it.

## Risks / Trade-offs

- [Fluent dependency weight and MSRV] → `fluent-bundle` is pure-Rust, no C
  tooling; pin versions, add to `cargo deny` allowlist review; icu4x MF2 noted
  as the documented swing position if Fluent stagnates.
- [422 breaks existing 400-branching clients early] → accepted: v1/dev phase,
  called out **BREAKING** in proposal and changelog; 400 still appears for
  malformed input so blind "== 400" code keeps *some* behaviour.
- [Registry/lint drift (code without de-message ships to prod)] →
  bundle-coverage lint fails CI before merge; golden tests cover extension
  drift.
- [S1 judgment erodes: someone adds an S2-ish field to a whitelisted code] →
  golden-file diff surfaces every extension change in review + ast-grep S2
  lint; ADR names the escalation rule (S1 only after the authz gate).
- [Golden-file snapshots get rubber-stamped] → diffs only appear when
  *extensions* change — precisely the audit-worthy events; low noise by design.
- [One more CI ast-grep job slows pipeline] → single rule, staged-files scope
  in pre-commit, full-tree in CI like the existing `cqrs-boundary` job.

## Migration Plan

1. **Tranche 1 (envelope)**: problem builder + `application/problem+json` +
   content-type everywhere + a registry skeleton with framework codes; status
   semantics switch incl. 422; auth middleware rejections and the panic
   fallback routed through the shared problem builder; OpenAPI `ProblemDetails`
   schema. Clients migrate to `code`.
2. **Tranche 2 (structure)**: `DomainError` → structured variants + full code
   registry + extension whitelists + golden tests + S2 ast-grep rule.
3. **Tranche 3 (i18n)**: Fluent wiring, `locales/de|en/errors.ftl`,
   `Accept-Language` extractor, coverage lint.

Each tranche is independently mergeable; Tranche 1 alone is already the full
breaking interface change so clients only migrate once. Rollback per tranche =
revert; DB untouched.

## Open Questions

- `docs.breakdown.example` base of `type` URIs — final docs host (and whether
  a static generated page per code ship_dev-mäßig or links into the OpenAPI
  UI). Decide at Tranche-1 implementation; registry takes the base from config
  so hosting changes are non-breaking.
- Ukrainian/other future locales ordering in the fallback chain — deferred to
  locale #3; chain is config, not code.
