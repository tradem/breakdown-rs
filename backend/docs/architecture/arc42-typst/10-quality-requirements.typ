// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: kimi-k3 (neuralwatt)
// Co-authored-by: gemini-4-carbon (google)

#import "template.typ": *


= Quality Requirements

== Quality Tree

#diagram("quality-tree", caption: [Breakdown RS quality tree across backend and Flutter client])

== Quality Scenarios

=== Scenario 1: Full Event-Sourced Round-Trip (Tier 4)

- *Trigger*: a pull request changes `crates/core`, `crates/infra`, `crates/api`,
  or `crates/integration-tests`.
- *Response*: the `integration-tests` workflow runs Tiers 1–4 against ephemeral
  PostgreSQL and SierraDB containers. Tier 4 sends a live command, checks raw
  SierraDB `ESCAN` persistence, and asserts projection catch-up.

=== Scenario 2: Hexagonal and Static Lint Compliance

- *Trigger*: code adds a disallowed `crates/core` dependency, dynamic SQL
  string formatting, an ignored `Result`, or a `throw` in Flutter `data/` or
  `domain/`.
- *Response*: CI fails immediately in `cargo deny check bans`, `rust_arkitect`,
  `ast-grep` (`architecture-checks.yml`), or `breakdown_lints_runner`
  (`flutter-ci.yml`) and reports the offending file and rule.

=== Scenario 3: Concurrent Cross-Aggregate Uniqueness

- *Trigger*: two concurrent clients send `POST /v1/seasons` with the same
  `(project_id, number)` before the projection row exists.
- *Response*: one request claims `reservation-seasnum-*` with
  `ExpectedVersion::Empty` and returns `201 Created`. The losing request fails
  the SierraDB version check and receives `409 season.number-already-exists`
  without writing a duplicate `SeasonCreated` event (#adr-ref(num: "036", slug: "es-native-reservation-streams-cross-aggregate-uniqueness", title: "Reservation Streams")).

=== Scenario 4: RFC 9457 Error Contract and Client Localization

- *Trigger*: an API request fails domain validation or authorization.
- *Response*: the API returns `application/problem+json` with a registered
  `code` from `error_registry.rs` and Fluent-localized `detail`. The Flutter
  client matches `code` and renders its localized ARB message (#adr-ref(num: "031", slug: "http-error-surface", title: "HTTP Error Surface"),
  #adr-ref(num: "034", slug: "flutter-app-localization-gen-l10n", title: "Flutter Localization")).

=== Scenario 5: Projector Idempotency and Poison-Event Isolation

- *Trigger*: SierraDB redelivers an already projected event, or a projector hits
  a permanent SQL constraint error after retries.
- *Response*: version guards (`WHERE version < $N`) turn redelivered events into
  safe no-ops. Permanent errors write a row to `projection_dead_letter`, advance
  the checkpoint in the same transaction, and report status on
  `GET /v1/ops/projector-health` without crashing the projector loop.

=== Scenario 6: Byte-Identical Timestamp Replay

- *Trigger*: the system replays pre-migration event streams after replacing
  `chrono` with `jiff`.
- *Response*: `jiff::Timestamp` serializes identical RFC 3339 strings, so
  `projection_audit.event_key` hashes match existing rows and produce zero
  duplicate audit entries (#adr-ref(num: "040", slug: "jiff-replaces-chrono", title: "jiff Replaces chrono")).

=== Scenario 7: Client Projection-Lag Sync and Offline Read Survival

- *Trigger*: a mobile user creates an outfit over a slow link or opens a screen
  during a brief signal drop.
- *Response*: after a `201` reply, the Riverpod controller shows an optimistic
  overlay and runs bounded retries until the projected row arrives. During a
  network drop, Drift SQLite serves the last projected view while write buttons
  show clear retry errors.
