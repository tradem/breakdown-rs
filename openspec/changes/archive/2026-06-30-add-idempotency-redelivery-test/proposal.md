## Why

ADR-016 task 4.3 and PR #24 both require a second Tier-4 test variant that verifies projector idempotency under event redelivery (same event appended twice). The current `sierradb_round_trip.rs` only covers the happy-path `SceneCreated` round-trip but does not test that mutation-event projectors tolerate duplicate delivery without corrupting the projection — a property the `ON CONFLICT DO UPDATE` / `DO NOTHING` upsert pattern promises by construction but has never been verified against the real SierraDB + Postgres tiers.

## What Changes

- Add a new `#[tokio::test]` in `crates/integration-tests/tests/sierradb_round_trip.rs` that creates a scene, then appends a `CharacterAssigned` event **twice** (redelivery) and asserts the projection row remains correct — no duplicate rows, no version corruption.
- Update `docs/architecture/adrs/ADR-016-sierradb-runtime-and-round-trip.md` task 4.3 to mark it complete and reference the new test.

## Capabilities

### New Capabilities
<!-- No new capabilities — this extends an existing test specification. -->

### Modified Capabilities
- `sierradb-round-trip-testing`: Add a requirement for a Tier-4 idempotency-under-redelivery test variant, covering a mutation event (e.g., `CharacterAssigned`) appended twice and asserting the projection remains unchanged / non-duplicated.

## Impact

- **Code:** `crates/integration-tests/tests/sierradb_round_trip.rs` (new test function)
- **Docs:** `docs/architecture/adrs/ADR-016-sierradb-runtime-and-round-trip.md` (task 4.3 status update)
- **Dependencies:** No new crate dependencies — reuses existing `redis` client, `SceneRepositoryImpl`, `spawn_postgres`, `spawn_sierradb`, and `scene_repo_pool` helpers already available under the `testing` feature.
