// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors

== Quality Requirements

=== Quality Scenarios

==== Scenario 1: Integration Test Pipeline

- **When** a developer pushes or merges code touching `crates/core`, `crates/infra`,
  `crates/api`, or `crates/integration-tests`.
- **Then** the `integration-tests` CI job runs and passes:
  - Tiers 1–3: Postgres-only projector/repository tests
  - Tier 4: full `command → SierraDB → projector → Postgres projection → read query` round-trip

==== Scenario 2: Architecture Test Compliance

- **When** a developer adds a forbidden `use` statement or Cargo dependency to `crates/core`.
- **Then** either `cargo deny check bans` (dependency-level) or `cargo test -p architecture_tests`
  (source-level with `rust_arkitect`) fails with a clear message identifying the violation,
  the file, and the applicable rule. See ADR-017 for details.

==== Scenario 3: Mutation Test Coverage

- **When** a developer runs `cargo mutants --in-diff` on changed code.
- **Then** no mutants survive; if any do, additional tests are written to cover the gap.
