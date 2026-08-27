## Context

The existing Tier-4 round-trip test (`eappend_scene_created_round_trips_into_projection`) in `crates/integration-tests/tests/sierradb_round_trip.rs` covers only the happy-path: a `SceneCreated` event is appended to SierraDB, the projectors catch up, and the projection row is asserted. ADR-016 task 4.3 and PR #24 both call for a **second** Tier-4 variant that verifies projector idempotency under event redelivery — appending the same mutation event twice and asserting the projection remains correct.

The projectors use `ON CONFLICT DO UPDATE` (for upsert variants) or `INSERT ... ON CONFLICT DO NOTHING` patterns, which are idempotent by construction. However, this property has never been verified in an integration test against the real SierraDB + Postgres tiers.

## Goals / Non-Goals

**Goals:**
- Add a single `#[tokio::test]` that exercises a mutation event (e.g., `CharacterAssigned`) appended **twice** (simulating redelivery) and asserts the projection row is unchanged / not duplicated.
- Reuse the existing test harness (`spawn_postgres`, `spawn_sierradb`, `scene_repo_pool`, `await_scene_projection`) without modification.
- Update ADR-016 task 4.3 status to `done`.

**Non-Goals:**
- Refactoring or changing the existing projector upsert logic — those are already idempotent by construction.
- Adding a second test file — the new test lives alongside the existing one in `sierradb_round_trip.rs`.
- Modifying the `CommandService` or introducing new infrastructure helpers.

## Decisions

### Test structure: EAPPEND the same `CharacterAssigned` event twice

The test flow:
1. Spin up Postgres + SierraDB, spawn scene projector.
2. Append a `SceneCreated` event and await its projection (reuse `await_scene_projection`).
3. Append a `CharacterAssigned` event **once**, then await the updated projection and assert the character appears in `assigned_characters`.
4. Append the **identical** `CharacterAssigned` event **again** (same `id`, `character_id`, `version`), and assert the projection row is identical — no duplicate rows, no version/count change.

This directly tests the `ON CONFLICT DO UPDATE` pattern in the scene projector: the second upsert should overwrite with the same data, producing no observable change.

**Alternative considered:** Using `CharacterRemoved` as the mutation event. Rejected because `CharacterAssigned` exercises the array-upsert path (`assigned_characters`), which is more interesting for idempotency (the projector must not append a duplicate character ID).

### Use `scene_repo_pool` for direct projection reads

The existing test already uses `SceneRepositoryImpl::find_by_id` for assertions. For the idempotency variant, we may also inspect the raw projection row via `scene_repo_pool` to assert `version` and row count explicitly, but this is an implementation detail handled in the task.

### No new `await_scene_projection` variant needed

The existing bounded-retry helper (`await_scene_projection`) works for both the initial create and the mutation update. After the first `CharacterAssigned`, waiting until the `assigned_characters` array reflects the change is sufficient. After the second (duplicate) append, the same wait with a tighter assertion confirms no change occurred.

## Risks / Trade-offs

- **Flakiness from eventual consistency**: The second EAPPEND may be processed by the projector before the first assertion runs. Mitigation: the test explicitly awaits the projection state after each EAPPEND before proceeding.
- **Container startup overhead**: The test starts both Postgres and SierraDB containers, which is already the baseline cost for Tier-4 tests. No additional containers needed.
