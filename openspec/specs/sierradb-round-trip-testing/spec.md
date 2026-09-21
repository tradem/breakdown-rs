# SierraDB Round-Trip Integration Testing

## Purpose

Define the Tier-4 integration test that drives the full
`command → SierraDB event persisted → PostgresProcessor catches up → read via
*Repository adapter asserts the projection row` chain, extending the ADR-014
Testcontainers harness with a SierraDB container.

## Requirements

### Requirement: Tier-4 SierraDB round-trip integration test
The `crates/integration-tests` crate SHALL provide at least one integration test
that, against ephemeral SierraDB and Postgres containers, drives a real
`CommandService` command, asserts the resulting event is persisted in SierraDB,
waits for the per-aggregate `PostgresProcessor` to catch up, and asserts the
projection row is queryable via the read `*Repository` adapter — completing the
full `command → event → SierraDB → projector → Postgres projection → read
query` chain deferred by `persistence-layer-v1` (Tiers 1–3) and ADR-014/015.

#### Scenario: Command round-trips into a projection row
- **WHEN** a `Create*` command is dispatched to an aggregate backed by the real
  SierraDB event store
- **THEN** the resulting event is persisted in SierraDB (verifiable via a
  read/`ESCAN`)
- **AND** the projector updates the corresponding `projection_*` table
- **AND** a read query via the `*Repository` adapter returns the projection row
  with the created entity's UUIDv7 id, project id, and version

#### Scenario: Eventual consistency is asserted with a bounded wait
- **WHEN** the projector lags the event append
- **THEN** the test retries the projection read for a bounded time before failing
- **AND** on failure it reports the lag explicitly rather than a bare assertion
  error

### Requirement: One testcontainers harness, extended
The SierraDB round-trip test SHALL reuse the existing ADR-014 testcontainers
harness pattern (extend it to also start a SierraDB container) rather than
introducing a parallel test-infrastructure crate. If upstream provides a
`sierradb` testcontainers module it SHALL be used; otherwise a small local
`testcontainers::Image` implementation SHALL be added to
`crates/integration-tests`.

#### Scenario: No second test harness crate
- **WHEN** the test infrastructure is inspected
- **THEN** there is exactly one integration-test crate
  (`crates/integration-tests`)
- **AND** both Postgres and SierraDB containers are provisioned through helpers
  in that crate

### Requirement: Tier-4 test is excluded from the cargo-mutants surface
Consistent with ADR-014 and `persistence-layer-v1`, the Tier-4 round-trip tests
SHALL be excluded from `cargo-mutants` (black-box integration tests consume only
the public API of `core`/`infra`).

#### Scenario: Mutants do not touch the round-trip test
- **WHEN** `cargo mutants` runs
- **THEN** the SierraDB round-trip test bodies are not in the mutation surface

### Requirement: Tier-4 idempotency-under-redelivery test variant
The `crates/integration-tests` crate SHALL provide a second Tier-4 integration test that, against ephemeral SierraDB and Postgres containers, appends the same mutation event (e.g., `CharacterAssigned`) twice and asserts the projection row remains unchanged — no duplicate rows, no version drift, and no data corruption — verifying the projector upsert path is idempotent under event redelivery.

#### Scenario: Mutation event appended twice yields identical projection
- **WHEN** a scene has been created and projected
- **AND** a `CharacterAssigned` event is appended to SierraDB via `EAPPEND` with a specific version
- **AND** the projector catches up and the projection reflects the assigned character
- **AND** the **identical** `CharacterAssigned` event (same `id`, `character_id`, `version`) is appended again via `EAPPEND`
- **THEN** the projector catches up on the redelivered event
- **AND** the projection row is identical to the state after the first append — no duplicate `assigned_characters` entries, no version change, no additional rows

#### Scenario: Idempotency test follows the same bounded-retry pattern
- **WHEN** the projector lags any event append in the idempotency test
- **THEN** the test retries the projection read for a bounded time before failing
- **AND** on failure it reports the lag explicitly rather than a bare assertion error

## Deviations

### Former deviation: `CommandService` segment not exercised (issue #25, resolved 2026-09-21)

**Resolved.** As shipped by PR #24, the Tier-4 tests appended events directly
to SierraDB via `EAPPEND` and did **not** drive a real `CommandService`
command — a deliberate workaround for the SierraDB v0.3.1 single-node bug
where the read path (`ESCAN` / `ReadStream` / `resync_with_db`) failed with
`PartitionUnavailable` / `broken pipe`.

The deviation is closed as of 2026-09-21: the Tier-4 variant
`command_service_create_scene_round_trips_via_escan` now drives a real
`CreateScene` + `UpdateSceneDetails` command through the production
`SceneCommandsImpl` adapter, verifies the persisted events via raw `ESCAN`
reads, and asserts the projector catch-up through the read adapter — the
`command →` segment of the chain is exercised against the real tiers. The
upstream bug never received a fix (v0.3.1 remains the latest `tqwewe/sierradb`
tag); it stopped reproducing on the current client stack (vendored `kameo_es`
0.2.0, `sierradb-client` 0.3.1, `redis` 1.7), empirically verified with 5/5
stable runs against the pinned container. The `EAPPEND`-based tests remain as
additional projector idempotency/redelivery coverage. Documented in ADR-016 §5.
