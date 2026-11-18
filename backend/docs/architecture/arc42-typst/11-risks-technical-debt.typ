// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: kimi-k3 (neuralwatt)
// Co-authored-by: gemini-4-carbon (google)

#import "template.typ": *


= Risks and Technical Debt

== Active Risks

#table(
  columns: 4,
  table.header([Risk], [Likelihood], [Impact], [Mitigation]),
  [CQRS projection lag visible to mobile users], [Medium], [Medium], [Client optimistic overlays, bounded-retry refetch, and split app/projector DB pools (`#900`).],
  [Event payload wire drift breaks replay or duplicates audit keys], [Low], [High], [Keep persisted keys (`series_id`) and `jiff` RFC 3339 output stable, and run replay contract tests.],
  [External LLM provider rate limits or outages], [Medium], [Low], [AI import is opt-in, and circuit breakers, bounded retries, and Garage blobs protect workers.],
  [Root CA rotation or expired pin locks out mobile clients], [Low], [High], [Pin long-lived public ACME roots (`ISRG Root X1`/`X2`), not 90-day leaf certs (#adr-ref(num: "032", slug: "flutter-client-tls-pinning-rotation", title: "Client TLS Pinning")).],
  [Third-party container or dependency drift], [Medium], [Medium], [Pin Docker image digests, Cargo/Pub lockfiles, GitHub Action SHAs, and run `cargo-deny`.],
)

== Known Technical Debt

=== Historical `series_id` Key in Persisted Events

Rust types, SQL columns, and OpenAPI fields now use `ProjectId` and
`project_id` (#adr-ref(num: "035", slug: "production-kind-flexible-hierarchy", title: "Production-Kind-Flexible Hierarchy")).
Persisted event payloads (`SeasonCreated`, `BlockCreated`, `EpisodeCreated`, and
`EventMetadata`) keep the JSON/CBOR key `series_id` on purpose. Renaming that
re-serialized key changes `projection_audit.event_key` during replay.

=== PostgreSQL-Backed AI Import Queue

The `ai_import` job lifecycle lives in PostgreSQL tables rather than SierraDB
streams (#adr-ref(num: "030", slug: "ai-import-bounded-context", title: "AI Import")).
This keeps transient retry counters and lease heartbeats out of the immutable
domain log, at the cost of maintaining owner-fenced SQL transitions separately.

=== No Native Mutation Tool for Dart

No production-grade mutation test runner exists for Dart and Flutter today.
`frontend-flutter/` compensates with `coverde` diff coverage thresholds, golden
widget tests, and mandatory `Ok`/`Err` assertions on every `Result` pipeline.

=== Production Root CA Bundle Placeholder

`frontend-flutter/assets/certs/dev/ca.pem` carries the active development CA,
while `assets/certs/prod/ca.pem` stays a placeholder until the production
domain cutover embeds the final ISRG root bundle (#adr-ref(num: "032", slug: "flutter-client-tls-pinning-rotation", title: "Client TLS Pinning")).

=== Read-Only Offline Mode on Mobile

The Flutter client caches read projections in Drift SQLite, and write commands
must use an active network connection. Offline command queuing is deferred
because offline conflict resolution and `project_id` enrichment need dedicated
specs.

== Resolved Items (Kept for Context)

- *`chrono` unmaintained advisory (`RUSTSEC-2026-0543`)*: migrated workspace to
  `jiff` + `infra::db_time` (#adr-ref(num: "040", slug: "jiff-replaces-chrono", title: "jiff Replaces chrono")).
- *Cross-aggregate uniqueness race (`#404` / `#586`)*: closed at the write
  boundary with synthetic `reservation-*` streams and reaper (#adr-ref(num: "036", slug: "es-native-reservation-streams-cross-aggregate-uniqueness", title: "Reservation Streams")).
- *Monolithic `Costume` aggregate*: split cleanly into `Piece` (fundus) and
  `Outfit` (character look), and deleted the obsolete `Calculation` context.
- *Single Postgres DML pool contention (`#900`)*: split into separate `app` and
  `projector` connection pools so AI apply bursts never starve behind projectors.
