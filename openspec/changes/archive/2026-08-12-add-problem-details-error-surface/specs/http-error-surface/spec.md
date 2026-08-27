<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: kimi-k3 (neuralwatt) -->

# http-error-surface Specification (delta: ADDED)

## ADDED Requirements

### Requirement: RFC 9457 problem+json error body

Every HTTP error response (status ≥ 400) produced by the API — including
domain errors, auth middleware rejections, Axum extractor/rejection failures,
unknown-route responses, payload-limit rejections, and the panic fallback —
SHALL carry `Content-Type: application/problem+json` and a body conforming to
RFC 9457 with the members `type`, `title`, `status`, `detail`, plus the
extensions `code` and `trace_id`.

#### Scenario: Domain not-found returns problem+json
- **WHEN** a client requests `GET /characters/{id}` for a non-existent character with a valid token
- **THEN** the response SHALL have status 404, `Content-Type: application/problem+json`
- **AND** the body SHALL contain `"status": 404`, a non-empty `type` URI, English `title`, `code` equal to the registry entry for that failure, and a non-empty hex `trace_id`

#### Scenario: Malformed JSON body is a problem, not plain text
- **WHEN** a client POSTs a syntactically invalid JSON body to any JSON-consuming endpoint
- **THEN** the response SHALL have status 400 and `Content-Type: application/problem+json`
- **AND** the body SHALL carry `code` `http.bad-json-body`

#### Scenario: Unknown route returns a problem
- **WHEN** a client requests a path that matches no route
- **THEN** the response SHALL have status 404 and `Content-Type: application/problem+json`
- **AND** the body SHALL carry `code` `http.route-not-found`

#### Scenario: Unhandled panic returns a static problem
- **WHEN** a handler panics
- **THEN** the response SHALL have status 500, `code` `http.internal-error`
- **AND** `detail` SHALL be a static localized sentence that contains no internal error text, no stack trace, and no data values
- **AND** the failing span's `trace_id` SHALL be present in the body

### Requirement: Stable machine-readable error codes and registry

The API SHALL assign every distinguishable failure a stable code of the form
`{context}.{reason}` with lowercase kebab-case segments (context examples:
`scene`, `costume`, `scene-shoot`, `photo`, `membership`, `concurrency`,
`http`, `auth`). The set of codes SHALL be defined in a single code registry
that is the source for (a) the `code` member, (b) the `type` URI anchor, and
(c) the localization message key. A published code SHALL NOT be reused or
removed; removal requires an API major version bump per ADR-021.

#### Scenario: `type` URI is derived from the code
- **WHEN** any problem is emitted with `code` `scene.already-scheduled`
- **THEN** `type` SHALL equal the configured documentation base URL joined with `/problems/scene.already-scheduled`

#### Scenario: Code registry rejects an unregistered emission
- **WHEN** the problem builder is asked to emit a code absent from the registry
- **THEN** the build SHALL fail at compile time or in the registry unit tests (never silently at runtime)

### Requirement: Per-code extension whitelist with S0/S1/S2 privacy classification

Problem extensions beyond `code`/`trace_id` SHALL only contain fields declared
in the registry entry for that code. Every extension field SHALL be
classified: **S0** (identifier supplied by the client in the request — always
allowed), **S1** (aggregate identifier within the caller's authorized
scope — allowed only in handlers that ran their authorization gate before the
failure), **S2** (person identifiers such as OIDC `sub` or e-mail, and any
cross-tenant data — never allowed). Internal error text, database errors, and
person identifiers SHALL NOT appear in any problem member.

#### Scenario: Conflict exposes the in-scope conflicting resource
- **WHEN** scheduling a scene on a shooting day fails because the scene is already scheduled on another day, and the caller passed the authorization gate for that season
- **THEN** the problem extensions SHALL include the offending shooting day id (S1), typed by name (e.g. `offending_shooting_day_id`)

#### Scenario: Person identifier is never echoed
- **WHEN** inviting a member fails because the identity is already invited
- **THEN** the problem SHALL NOT contain the invited OIDC `sub` or e-mail anywhere in the body

#### Scenario: Extension diff is review-visible
- **WHEN** a developer adds or changes an extension field for a code
- **THEN** the golden-file serialization test for that code SHALL fail until the expected JSON snapshot is updated

### Requirement: Status-code semantics and existence-oracle policy

The API SHALL use status codes consistently: 400 for malformed requests
(syntax, headers, path parameters), 422 for semantically invalid but
well-formed documents (domain validation), 401 for missing/invalid
authentication, 403 for authenticated callers lacking permission, 404 for
resources not found or deliberately hidden, 409 for state conflicts including
optimistic-concurrency `concurrency.version-mismatch`, 503 for upstream
unavailability. The existence-oracle policy (returning 404 for non-members'
requests to existing foreign resources) SHALL be documented in ADR-031 and
applied uniformly.

#### Scenario: Domain validation failure returns 422
- **WHEN** a client submits a well-formed JSON document that violates a domain validation rule (e.g. empty costume category name)
- **THEN** the response SHALL have status 422 (RFC 9110 §15.5.21), not 400

#### Scenario: Version conflict returns 409 with typed parameters
- **WHEN** a command fails optimistic-concurrency checking
- **THEN** the response SHALL have status 409, `code` `concurrency.version-mismatch`
- **AND** extensions SHALL include `expected_version` (S0, client-supplied) and MAY include `current_version`

### Requirement: Debugging correlation via trace id

Every problem response SHALL include `trace_id` with the W3C trace identifier
of the request's root OpenTelemetry span, so support can correlate a
user-visible failure with server telemetry without log access. The
dereferenceable `instance` URI of RFC 9457 SHALL NOT be used in this version.

#### Scenario: Trace id matches server span
- **WHEN** a request fails with any 4xx/5xx problem
- **THEN** the `trace_id` extension SHALL equal the trace id recorded in the request's otel span for the same request

### Requirement: Single problem builder at the HTTP boundary

All error sources (domain `IntoResponse`, auth middleware, extractor
rejections, payload limits, unknown routes, panic fallback) SHALL construct
their response through one shared problem builder, so the envelope, content
type, and trace-capture logic have exactly one implementation.

#### Scenario: Auth rejection comes through the same envelope
- **WHEN** a request arrives without a bearer token
- **THEN** the response SHALL have status 401, `Content-Type: application/problem+json`, and `code` `auth.unauthenticated` — structurally identical to a domain problem

#### Scenario: Payload too large is a problem
- **WHEN** a client exceeds a body size limit
- **THEN** the response SHALL have status 413, `Content-Type: application/problem+json`, and `code` `http.payload-too-large`
