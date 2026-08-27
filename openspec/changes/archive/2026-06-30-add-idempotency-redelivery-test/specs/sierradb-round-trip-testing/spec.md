## ADDED Requirements

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
