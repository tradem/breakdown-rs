## 1. Add idempotency-under-redelivery test

- [x] 1.1 Add `eappend_character_assigned_twice_is_idempotent` test function to `crates/integration-tests/tests/sierradb_round_trip.rs` — reuses `spawn_postgres`, `spawn_sierradb`, `await_scene_projection`, and `spawn_scene_projector` from the existing test; appends a `SceneCreated` event, then a `CharacterAssigned` event twice with identical payload, asserting the `SceneView.assigned_characters` array contains exactly one entry and `version` is unchanged after the second append.
- [x] 1.2 Run `cargo test -p integration-tests sierradb_round_trip` locally (requires Docker) and verify both the existing `eappend_scene_created_round_trips_into_projection` and the new idempotency test pass.

## 2. Update ADR-016 task 4.3

- [x] 2.1 Update `docs/architecture/adrs/ADR-016-sierradb-runtime-and-round-trip.md` task 4.3 status from "pending" to "done" and add a reference to the new test function.
