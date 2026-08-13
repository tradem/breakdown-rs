// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: kimi-k3 (neuralwatt)

#import "template.typ": *


= Crosscutting Concepts

== Error Surface (RFC 9457)

#adr-ref(num: "031", slug: "http-error-surface", title: "HTTP Error Surface")

- All failures return `application/problem+json` built by a single problem builder.
- Problem codes are registered centrally (`error_registry.rs`) and exposed only via
  the `problem_codes!` macro.
- Handlers propagate `Result<_, ApiError>`; there is no per-handler status mapping.
- Extension fields are classified S0 / S1 / S2; S1 only after AUTHZ-GATE.
- `detail` is localized server-side (Fluent, `de` default) — never in core.

== Authentication and Authorization

- *Authentication*: OIDC JWT (#adr-ref(num: "010", slug: "authentication-with-oidc", title: "OIDC Auth")), validated against JWKS.
- *Authorization*: season-scoped role membership checked per handler; some
  endpoints (photo handlers) additionally call `AuthorizationPolicy` explicitly.
- *Dev toggle*: `DEV_AUTH_SUB` runs authentication in development without
  reaching an IdP; production never reaches it (#adr-ref(num: "018", slug: "oidc-jwt-validation-and-dev-auth-toggle", title: "OIDC JWT Validation & Dev-Auth Toggle").
- *Boundary*: `Requirement::Authenticated` middleware alone is not enough —
  sensitive handlers add their own AUTHZ-GATE inside the handler body.

== Event Sourcing and Sagas

- Events are immutable facts; state rebuilds by replaying.
- Sagas react to events by dispatching follow-up commands (e.g. `PhotoUploaded` → `GeneratePhotoVariants`).
- Sagas must never query a projection — any derived context comes from
  the event or command. The sole exception is the AI-import worker's
  deterministic mapping lookup, which uses an explicit
  `// ast-grep-ignore: cqrs-boundary` suppression per call (issue #148).
- Projectors are idempotent via version guards (`WHERE version < $N`) and correctly replayed.

== Error Classifications in Projectors and Workers

#table(
  columns: 3,
  table.header([Classification], [Example], [Behaviour]),
  [Transient (`ServiceUnavailable`)], [network hiccup, Garage down], [retry loop (`retry_transient`)],
  [Permanent (`ValidationError`)], [unsupported file type], [fall through to redelivery/dead-letter],
  [Not found (`NotFound`)], [expected path missing], [handle as success in delete paths],
)

#important[
  Never discard a fallible result with `let _ = <call>`. Propagate (`?` / `map_err`), handle explicitly, or suppress with
  `// ast-grep-ignore: discard-result` + justification.
]

== Observability

- Structured logging via `tracing` (spans on handlers, aggregates, projectors).
- Planned full OpenTelemetry export (#adr-ref(num: "011", slug: "observability-with-opentelemetry", title: "Observability with OpenTelemetry")).
- Projector lag measured; GC runs emit counters and dry-run logs first.

== Configuration

- Everything is env-driven; secrets never in code (gitleaks enforced).
- `REQUIRE_IN_TRANSIT_TLS` startup gate enforces TLS URLs in production
  (#adr-ref(num: "024", slug: "database-encryption-in-transit", title: "Database Encryption in Transit")).

== Domain Identifiers

- UUIDv7 only (`uuid::Uuid::now_v7()`); no sequential IDs anywhere.

// TODO: document report archival flow (ADR-022) once the production backup targets are stable
