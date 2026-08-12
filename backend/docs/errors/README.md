<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: kimi-k3 (neuralwatt) -->

# HTTP Error Surface

Every error response from the API is an RFC 9457 `application/problem+json`
document carrying a **stable machine code**, typed extension fields, a
`trace_id`, and an `Accept-Language`-localized `detail`. This is the contract
clients branch on — see [ADR-031](../architecture/adrs/ADR-031-http-error-surface.md)
for the decisions behind it.

| Document | Purpose |
|---|---|
| [error-codes.md](error-codes.md) | All 73 registered codes with status, title, extension fields (S0/S1), and `type` anchors |
| [client-migration.md](client-migration.md) | Migration guide: switch from `message` parsing to `code`-based handling |
| OpenAPI `x-code-registry` | Machine-readable registry mirror published in the API spec |

## Envelope

```json
{
  "type":       "https://docs.breakdown.example/problems/scene.already-scheduled",
  "title":      "Scene schedule conflict",
  "status":     409,
  "code":       "scene.already-scheduled",
  "detail":     "Die Szene ist bereits auf einem anderen Drehtag eingeplant.",
  "trace_id":   "4bf92f3577b34da6a3ce929d0e0e4736",
  "extensions": { "offending_shooting_day_id": "018g…" }
}
```

- `code` — the stable `{context}.{reason}` kebab-case machine identity. **This
  is what clients branch on.**
- `title` — constant English per code; never localized, cacheable.
- `detail` — localized server-side (Fluent bundles, `de` default / `en`),
  interpolating only whitelisted extension values. Human display text.
- `trace_id` — W3C trace id of the request span; maps a support screenshot
  1:1 to server telemetry.
- `type` — derived from the code (`{docs-base}/problems/{code}`); the docs
  host routes it to the per-code anchor in [error-codes.md](error-codes.md).
- `extensions` — declared per code; **only** fields on the code's whitelist
  are ever emitted.

## Status semantics

| Status | Meaning |
|---|---|
| 400 | Malformed request (JSON syntax, header, path/query parameter) |
| 401 | Missing/invalid authentication (`auth.unauthenticated`) |
| 403 | Authenticated but not permitted (`domain.forbidden` + member-role codes) |
| 404 | Resource not found — truthfully for members, hidden for non-members (oracle policy) |
| 409 | State conflict (`{agg}.already-*`, `concurrency.version-mismatch`) |
| 413 | Payload over the size limit |
| 422 | Well-formed but domain-invalid document (`{agg}.validation`, RFC 9110 §15.5.21) |
| 500 | Internal error (`http.internal-error`, static localized `detail` only) |
| 503 | Service temporarily unavailable (`domain.service-unavailable`, `auth.idp-unavailable`) |

**Existence-oracle policy:** requests from authenticated *non-members*
receive 404 for resources outside their scope — existence is never revealed
to them. Members receive truthful 404 vs 403/409 because membership already
implies visibility.

## Extension privacy classification (S0/S1/S2)

Every extension field of every code is declared in the registry and
classified (ADR-031 D4):

- **S0** — client-supplied identifiers (`id`, `expected_version`,
  `current_version`): always allowed, the client already has them.
- **S1** — aggregate identifiers within the caller's authorized scope (e.g.
  the conflicting shooting day in `scene.already-scheduled`): allowed **only**
  where the handler's authorization gate ran before the failure
  (`// AUTHZ-GATE:` pattern). These are the cheapest traceability lever for
  support tickets.
- **S2** — person identifiers (OIDC `sub`, e-mail) and cross-tenant data:
  **never** emitted. Enforced mechanically: undeclared fields do not compile
  to the wire, golden-file snapshots surface every extension diff in review,
  and an ast-grep rule bans `sub`/`email` references in problem-builder code.

## Localization

- Bundles: `crates/api/locales/<lang>/errors.ftl`, standard Fluent syntax
  (Pontoon/Weblate-importable verbatim).
- Negotiation: q-value-aware `Accept-Language` parsing against the supported
  set; fallback chain `requested… → de → en`; absent/garbage header → `de`.
- Message keys derive mechanically from codes
  (`scene.already-scheduled` → `problem-scene-already-scheduled`); the
  bundle-coverage lint fails CI when a code lacks a message in an active
  locale or a key has no registry code.
- Adding a locale = `locales/<lang>/errors.ftl` + one entry in
  `SUPPORTED_LOCALES` (`crates/api/src/problems/locale.rs`). The fallback
  chain is configuration, not code.

## Code lifecycle (deprecation rule)

- Published codes are **never reused**; removing one requires an API major
  bump (ADR-021).
- Deprecated codes keep their locale messages until removal — the
  orphan-key lint tolerates deprecated entries.
- Adding a code = one registry entry (`crates/core/src/error_registry.rs`)
  + de/en bundle messages + golden snapshot
  (`UPDATE_GOLDEN=1 cargo test -p api --test problem_golden`). The
  bundle-coverage lint and golden tests are the mechanical gate.
- The registry entries are declared through the single-source
  `problem_codes!` macro: a single invocation contains the whole registry,
  and each entry expands to both the `pub const` and its `PROBLEM_CODES`
  slot, so an unregistered code cannot exist (issue #232). A standalone
  `pub const ...: ProblemCode` outside that invocation is rejected by the
  `problem-code-registry` CI job, and a compile-time assertion keeps
  `PROBLEM_CODE_COUNT` in sync with the registry size.

## Registry

The single source of truth is `crates/core/src/error_registry.rs` — code,
status, constant English title, extension whitelist. The `problem_codes!`
macro emits each `pub const` and its `PROBLEM_CODES` entry from the same
invocation, so the constant list and the registry array can never drift
apart (issue #232); a standalone declaration outside the invocation fails
CI (`problem-code-registry` job). `type` URIs, Fluent keys, and the
OpenAPI `x-code-registry` extension are all derived from it, never stored
separately.
