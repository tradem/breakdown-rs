// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors

#import "template.typ": *


= Quality Requirements

== Quality Tree

#diagram("quality-tree", caption: [arc42 quality tree targets])

== Quality Scenarios

=== Scenario 1: Integration Test Pipeline

- *When* a developer pushes or merges code touching `crates/core`,
  `crates/infra`, `crates/api`, or `crates/integration-tests`.
- *Then* the `integration-tests` CI job runs and passes:
  - Tiers 1–3: Postgres-only projector/repository tests.
  - Tier 4: full `command → SierraDB → projector → Postgres projection → read`
    round-trip against ephemeral containers.

=== Scenario 2: Architecture Test Compliance

- *When* a developer adds a forbidden `use` statement or Cargo dependency
  to `crates/core`.
- *Then* either `cargo deny check bans` (dependency level) or
  `cargo test -p architecture_tests` (source level with `rust_arkitect`)
  fails with a clear message identifying the violation, the file, and the
  applicable rule. See #adr-ref(num: "017", slug: "architecture-testing-strategy", title: "Architecture-Testing Strategy").

=== Scenario 3: Mutation Test Discipline

- *When* a developer runs `cargo mutants --in-diff` on changed code.
- *Then* no mutants survive; if any do, tests are extended to kill them.

=== Scenario 4: Error Surface RFC 9457

- *When* the API encounters a domain or validation error.
- *Then* the response is `application/problem+json` with a stable code
  declared in `error_registry.rs`; the schema is covered by the
  `problem-golden.rs` golden snapshots, the `detail` localized server-side.

=== Scenario 5: Soll-Ist Report Idempotency

- *When* the same `ShootingDay.wrapped_at` event is replayed to the
  projection twice (crash recovery, subscriber reconnect).
- *Then* the projection does not corrupt existing data: the version guard
  (`WHERE version < $N`) keeps the row at the highest event version only.

// TODO: performance targets once measured against real production data
