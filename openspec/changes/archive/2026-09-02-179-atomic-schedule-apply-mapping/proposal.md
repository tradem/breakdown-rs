<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: longcat-2.0-free (opencode) -->

# Proposal: Retry-safe schedule-side scene-shoot apply (issue #179)

## Problem

`ScheduleApplyWorker::apply` (`crates/infra/src/ai/schedule_apply.rs`) runs a
three-step sequence per schedule row:

1. `mappings.find(preview_id, "scene-shoot:{scene}:{day}")` — skip if present
2. `scene_commands.schedule_on_shooting_day(...)` +
   `scene_shoot_commands.plan(PlanSceneShoot { id: SceneShootId::new(), .. })`
3. `mappings.insert(AiImportMapping { .. aggregate_version: version })`

Steps 2 and 3 are not one recoverable operation. If the process crashes (or
the mapping write fails) **after** `PlanSceneShoot` appended its event and
**before** the mapping row is durable, the retry finds no mapping, generates a
*fresh* `SceneShootId` and dispatches a second `PlanSceneShoot`. That lands on
a different stream, so the aggregate-level pair-uniqueness invariant
(`PairAlreadyExists`, keyed on stream identity) does not catch it — the retry
only fails later at the `uq_projection_scene_shoot_pair` unique constraint in
the projector, i.e. *after* the duplicate event is already business truth.

`resolve_day` has the identical window for `CreateShootingDay`.

A deterministic `SceneShootId` alone does not close the window, because the
mapping row also has to carry the resulting `aggregate_version`, which is only
known after a successful append.

## Design: reserve → command → confirm

Make the id **stable across retries** by persisting it *before* the command,
and make the version **recoverable** from the event store on the retry path.

### 1. Reservation (new port method, `core`)

```rust
// core::ai::AiImportMappingRepository (additive)
async fn reserve(&self, mapping: AiImportMapping) -> Result<AiImportMapping, DomainError>;
```

`reserve` is a **single** `INSERT ... ON CONFLICT (preview_id, draft_ref) DO
UPDATE ... RETURNING` statement, so it returns the *durable* mapping — either
the one just written or the one a previous attempt wrote. The degenerate
`DO UPDATE SET aggregate_kind = <itself>` is deliberate: only an
actually-updated row is visible to `RETURNING`, so a plain `DO NOTHING` would
return nothing on conflict and force a second read that races a concurrent
confirm. Self-assignment changes no value while still yielding the row. The
reservation carries `aggregate_version: AggregateVersion(0)`, which already
means "no version yet" in this codebase (`version_from_current(Empty)` →
`AggregateVersion(0)`), so **no migration is required**: the column is a
plain `BIGINT NOT NULL` and the existing `insert` upsert only advances a row
when `aggregate_version < EXCLUDED.aggregate_version`, which makes the
confirm step a strict monotonic advance over the `0` reservation.

`AiImportMapping` gains `is_reserved()` (`aggregate_version.0 == 0`) so
callers never hand-compare the sentinel.

### 2. Command dispatch with the reserved id

Both `CreateShootingDay` and `PlanSceneShoot` are dispatched with
`ExpectedVersion::Empty` by their command adapters. On a retry after a crash,
the stream already exists, so the adapter returns
`DomainError::VersionConflict { current }` — and `current` is exactly the
aggregate version the mapping needs. The worker treats that as a *recovery*
signal, not a failure: the reserved id is confirmed with `current`.

### 3. Confirm

`mappings.insert(...)` with the real version advances the reservation row
(0 → N). Because the id was already durable in step 1, any number of retries
converge on the same aggregate.

### Scene scheduling made idempotent (`core`, decided with the maintainer)

Between plan and mapping sits `ScheduleSceneOnShootingDay`. A retry
re-dispatches it against a scene that already links the day. Today the
aggregate answers `SceneError::AlreadyScheduled` → `DomainError::Conflict`,
which aborts the whole apply permanently and leaves the mapping unconfirmed
forever.

`SceneAggregate` therefore implements the `kameo_es` state-idempotency hook
for that command:

```rust
fn is_state_idempotent(&self, cmd: &ScheduleSceneOnShootingDay, _ctx: Context<'_, Self>) -> bool {
    self.shooting_day_ids.contains(&cmd.shooting_day_id)
}
```

`is_state_idempotent` is the *right* seam rather than `handle` returning
`Ok(vec![])`: an empty event vector becomes `ExecuteResult::Executed(vec![])`,
which `map_executed_result` rejects as
`DomainError::Conflict("command produced no events")`. The hook instead yields
`ExecuteResult::Idempotent { current_version }`, which the adapter already maps
to the current aggregate version — no adapter change at all.

Optimistic concurrency is unaffected: `EntityActorState::execute` checks
`ExpectedVersion` *before* consulting the hook, so a stale-version command
still fails with `IncorrectExpectedVersion` → `DomainError::VersionConflict`.

`handle` keeps returning `Err(SceneError::AlreadyScheduled)` as an
unreachable-in-production defensive guard (it is only reachable by calling the
aggregate directly, i.e. from `core` unit tests), so the "SHALL emit no event"
invariant holds at both layers. `UnscheduleSceneFromShootingDay` is left alone:
un-scheduling something that was never scheduled is a genuine client error, not
a converging retry.

**Observable change:** `POST /scenes/{id}/shooting-days` for an already
scheduled day now returns `200 OK` with the unchanged version instead of
`409 Conflict`. This is the idempotent-PUT semantic the endpoint should have
had; the spec text and aggregate test are updated accordingly.

## Non-goals

- No new table, no migration. The reservation reuses
  `ai_import.projection_ai_import_mapping` with the existing `0` sentinel.
- No distributed transaction between SierraDB and Postgres. The protocol is
  crash-convergent, not atomic in the 2PC sense — which is what the issue
  asks for ("a stable reservation, an atomic persistence boundary, **or an
  equivalent mechanism**").
- No change to `ApplyWorker` (script side): scene creation there is driven by
  explicit user `ApplyMappingDecision`s and `UpdateSceneDetails` is already
  convergent.

## Tests

Deterministic, no timing:

- `crates/infra/src/ai/tests.rs`
  - reservation is written before the command (a fake that fails the plan
    command asserts the reservation row already exists)
  - a mapping-write failure after a successful `PlanSceneShoot`, then a retry,
    plans **exactly once** and confirms the mapping (issue AC #1 + #2)
  - the same for `CreateShootingDay` in `resolve_day`
  - a crash-simulating fake that returns `VersionConflict { current }` from
    `plan` proves the version is recovered into the mapping (AC #4)
  - the existing create-and-reuse test still passes (AC #3)
- `crates/core/tests/scene_aggregate.rs`
  - `is_state_idempotent` is `true` for an already-linked day and `false`
    otherwise; `handle` keeps its defensive `AlreadyScheduled` rejection
- `crates/api/tests/common/mod.rs` + `handlers/test_helpers.rs`: fakes
  implement `reserve`.

## Version bumps

| Crate | Previous | New | Bump type | Reason |
|---|---|---|---|---|
| `core` | 0.7.0 | 0.7.0 | none | Already unreleased-MINOR this cycle; the additive `reserve` port method and the idempotent schedule handler fold into the pending 0.7.0 |
| `infra` | 0.11.0 | 0.11.0 | none | Already unreleased this cycle; worker-internal protocol change folds into pending 0.11.0 |
| `api` | 0.6.0 | 0.6.0 | none | Already unreleased this cycle; only fakes and the re-pin, both already at the pending versions |
