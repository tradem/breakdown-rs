## ADDED Requirements

### Requirement: Tier-4 optimistic-concurrency round-trip through CommandService
The `crates/integration-tests` crate SHALL provide a Tier-4 integration test that, against ephemeral SierraDB and Postgres containers and through the real `CommandService` (not via direct event-store/`EAPPEND` bypass), drives the canonical OCC round-trip: dispatch a `Create*` command, read the returned `AggregateVersion`, wait for the per-aggregate `PostgresProcessor` to catch up, read the projection row's `version`, and dispatch a follow-up `update_*` command whose expected version equals the value obtained from the create reply and the projection row. The test SHALL assert that the follow-up update succeeds (no spurious `VersionConflict`) and that the create-reply version, the projection version, and the next expected version are identical. This test is the regression guard for the stream-version/domain-version divergence tracked in issue #31 and is gated on issue #25 making `CommandService` available to the Tier-4 harness.

#### Scenario: Create-reply version round-trips into a successful update
- **WHEN** a `Create*` command is dispatched to an aggregate backed by the real SierraDB event store via `CommandService`
- **THEN** the command reply returns `AggregateVersion::INITIAL` (`1`)
- **AND** after the projector catches up, the `projection_*.version` column is `1`
- **AND** a subsequent `update_*` command dispatched with `version = AggregateVersion(1)` succeeds with no `VersionConflict`

#### Scenario: Eventual consistency is asserted with a bounded wait
- **WHEN** the projector lags the create/append in the OCC round-trip test
- **THEN** the test retries the projection read for a bounded time before reading the version
- **AND** on failure it reports the lag explicitly rather than a bare assertion error

#### Scenario: OCC round-trip test is excluded from the cargo-mutants surface
- **WHEN** `cargo mutants` runs
- **THEN** the Tier-4 OCC round-trip test body is not in the mutation surface, consistent with the other Tier-4 tests
