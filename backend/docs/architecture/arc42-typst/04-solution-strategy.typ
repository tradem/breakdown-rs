// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: kimi-k3 (neuralwatt)
// Co-authored-by: gemini-4-carbon (google)

#import "template.typ": *


= Solution Strategy

== Architectural Pattern

Breakdown RS uses *Event Sourcing with Command Query Responsibility Segregation
(CQRS)* across a hexagonal Rust backend and a layered Flutter client. Commands
check domain rules in event-sourced aggregates. Projectors update flat
PostgreSQL tables asynchronously. Screens read projections only and never query
aggregates directly.

== Key Strategic Decisions

=== 1. Hexagonal Backend and Layered Client

- *Backend* (#adr-ref(num: "001", slug: "hexagonal-architecture", title: "Hexagonal Architecture")):
  `crates/core` holds pure domain logic, port traits, and read DTOs with zero
  infrastructure dependencies. `crates/infra` implements persistence, storage,
  sagas, and workers. `crates/api` wires dependencies manually in `main.rs`.
- *Client* (`frontend-flutter/`): `core/`, `auth/`, `data/`, `domain/`, and
  `features/` separate transport and Drift SQLite caching from UI widgets.
  Riverpod codegen (`@riverpod`) supplies compile-safe dependency injection.

=== 2. Event Sourcing, CQRS, and Reservation Streams

- *Write side* (#adr-ref(num: "002", slug: "event-sourcing-cqrs", title: "Event Sourcing and CQRS"),
  #adr-ref(num: "015", slug: "sierradb-event-store-postgres-projections", title: "SierraDB + PG Split")):
  aggregates run as `kameo_es` actors and append immutable CBOR events to
  SierraDB.
- *Cross-aggregate uniqueness* (#adr-ref(num: "036", slug: "es-native-reservation-streams-cross-aggregate-uniqueness", title: "Reservation Streams")):
  command adapters claim a synthetic `reservation-*` stream with
  `ExpectedVersion::Empty` before the aggregate append. Competing commands get
  a deterministic `409 Conflict` without orphan events.
- *Read side*: 30 `PostgresProcessor` consumers update flat PostgreSQL tables
  with version guards (`WHERE version < $N`).
- *CQRS hard rule*: write-side adapters, sagas, and aggregates never read
  projections to derive audit context. Only API handlers read projections before
  they send a command.

=== 3. Code-First Wire Contract and RFC 9457 Errors

- *OpenAPI contract* (#adr-ref(num: "006", slug: "utoipa-openapi-codegen", title: "utoipa OpenAPI"),
  #adr-ref(num: "021", slug: "api-versioning", title: "API Versioning")):
  `utoipa` derives `backend/openapi.yaml` from `/v1` Rust handlers. A script
  generates the Dart `breakdown_api` package from that file, and CI fails on
  drift on either side.
- *Error contract* (#adr-ref(num: "031", slug: "http-error-surface", title: "HTTP Error Surface")):
  every failure returns `application/problem+json` from the central
  `problem_codes!` registry. The client branches on the stable `code` field and
  never parses localized `detail` text.

=== 4. Defense-in-Depth Security and Pinned TLS

- *Identity and AuthZ* (#adr-ref(num: "010", slug: "authentication-with-oidc", title: "OIDC Auth"),
  #adr-ref(num: "018", slug: "oidc-jwt-validation-and-dev-auth-toggle", title: "OIDC Validation")):
  middleware checks RS256 OIDC JWTs and enforces deny-by-default `BlockMember`
  access. Non-block routes run explicit `// AUTHZ-GATE:` checks inside handlers
  and mirror those gates on the Flutter client.
- *End-to-end TLS* (#adr-ref(num: "024", slug: "database-encryption-in-transit", title: "Encryption in Transit"),
  #adr-ref(num: "025", slug: "https-edge-and-cert-rotation", title: "HTTPS Edge"),
  #adr-ref(num: "032", slug: "flutter-client-tls-pinning-rotation", title: "Client TLS Pinning")):
  Caddy handles public HTTPS, `step-ca` rotates 24-hour internal leaf
  certificates, and the Flutter app pins only its flavor Root CA.

=== 5. Replay-Safe Identifiers and Timestamps

- *UUIDv7* (#adr-ref(num: "004", slug: "use-uuidv7", title: "Use UUIDv7")):
  every entity, event, photo, and job uses time-ordered UUIDv7 identifiers.
- *jiff time types* (#adr-ref(num: "040", slug: "jiff-replaces-chrono", title: "jiff Replaces chrono")):
  `jiff::Timestamp` renders RFC 3339 strings that match historical `chrono`
  bytes one-for-one, so event replay never duplicates audit keys.

== End-to-End Command and Reconciliation Flow

#diagram("command-processing-sequence", caption: [Command execution, reservation claim, projection update, and client sync])

== Mechanical Guardrails Summary

#table(
  columns: 2,
  table.header([Architectural Rule], [Automated CI Check]),
  [`core` has no infra or web dependencies], [`cargo deny check bans` + `rust_arkitect` (`crates/architecture`)],
  [Write side never queries read projections], [`ast-grep` rule `cqrs-boundary`],
  [No panics in Rust or `throw` in Dart domain/data], [`clippy` (`unwrap_used`/`expect_used`/`panic` deny) + `breakdown_lints`],
  [No discarded fallible results], [`ast-grep` `discard-result` + `breakdown_lints` `discard_result`],
  [No string-interpolated SQL], [`ast-grep` rule `no-string-interpolation-sql`],
  [OpenAPI contract matches Rust and Dart code], [`openapi_drift` test + Flutter `regen-client.sh` diff check],
)
