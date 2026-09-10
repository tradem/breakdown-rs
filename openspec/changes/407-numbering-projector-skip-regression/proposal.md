<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: omen-alpha (opencode-go) -->

# DB-backed regression test for #404 — numbering projector skip + catch-up

## Why

Issue #407 asks for a testcontainer-backed regression test that machine-checks
the "inert for reports" claim of the #404 fix (log-only skip of permanent
invariant violations, PR #406).

**Drift check finding:** the SceneShoot half of the issue is already covered —
the owner pulled it forward into PR #406 (commit b672e94,
`crates/integration-tests/tests/scene_shoot_invariant_skip_tests.rs`) and
re-scoped the remainder on the issue: *extend the same coverage to the
numbering projectors (season/block/episode) and couple the assertions with the
#37 DLQ semantics if they change the skip behavior.* The remaining scope is
therefore:

1. Analog Tier-4 regression test for one numbering projector. **Season** is
   chosen (AC allows "einen der"): `SeasonCreated` needs no parent rows
   (`projection_season.series_id` is FK-free — the `Series` aggregate is a
   future seam), while Block/Episode would need parent seeding. The class is
   identical (`idx_projection_*_series_number` + SAVEPOINT skip).
2. Explicit **checkpoint-advance** assertion (the existing scene-shoot test
   proves catch-up only functionally via a trailing event; the season test
   additionally reads `sierradb_event_checkpoints` before/after).
3. **Warn-once** assertion: exactly one warn per skipped event, captured with
   a counting `tracing_subscriber::Layer` filtered by the poison event's
   `season_id` field (so parallel tests cannot pollute the count).

## What Changes

- New Tier-4 integration test
  `crates/integration-tests/tests/season_numbering_invariant_skip_tests.rs`:
  - Two `SeasonCreated` events with the same `(series_id, number)` under
    different stream ids → the second hits
    `idx_projection_season_series_number` (23505) and is savepoint-skipped.
  - A follow-up `SeasonRenamed` on the skipped stream is processed harmlessly
    (`UPDATE ... WHERE id = $1` → 0 rows, no new projection row, no error).
  - A trailing `SeasonCreated` (distinct number) on a third stream is
    projected — in-order processing proves the checkpoint advanced past the
    poison event; additionally the `sierradb_event_checkpoints` sequence for
    `projection_id = 'season'` strictly increases.
  - Exactly one warn (constraint + `season_id`) is captured per skipped event.
- No production code changes. No version bumps (`none`).

## Impact

- **Code:** one new test file (Tier 4: Postgres + SierraDB testcontainers).
- **Docs:** `docs/operations/runbooks.md` unchanged — the test now
  machine-checks the documented catch-up procedure instead of only describing
  it.
- **Risk:** the counting layer relies on the global default subscriber being
  installed once per test binary; the counter is filtered by the poison event
  id, so parallel tests within the binary cannot cross-contaminate counts.
