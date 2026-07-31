// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4-flash (opencode-go)

# Issue #147 — Carry `series_id` in command structs (CQRS)

> Systematic implementation plan for migrating the remaining **10 command
> adapters** away from resolving `series_id` via read-model projections
> (`*_repo.find_by_id()`), following the `MembershipCommandsImpl` precedent
> (commit `1ebb97a`).

## 1. Problem statement

`EventMetadata` carries `series_id: Option<SeriesId>` for the audit projector
(which keys on `series_id`). Currently 10 command adapters (write-side) resolve
this value by querying read-model projections — a CQRS-boundary violation
(AGENTS.md §1, hard rule). It creates hidden coupling to projector presence and
projection lag: tests that dispatch commands without the parent projector
running fail with `Entity not found`, and production risks silent audit gaps
when a parent projector lags (see also AGENTS.md §1 and the CQRS-boundary rule).

**Solution:** `series_id: Option<SeriesId>` becomes a field on each command
struct. The API edge (handlers — the legitimate read-model boundary) resolves
`series_id` from projections and populates the command before dispatch. Sagas
resolve it from event data or their own `resolve_series_id` helper. The adapter
becomes dumb: `EventMetadata.series_id = cmd.series_id`.

## 2. Scope

10 adapters, **99** `find_by_id` read-model lookups, **46** command structs:

| Adapter | Lookups | Resolution chain | Commands to extend |
|---|---|---|---|
| `SeasonCommandsImpl` | 1 | `find_by_id(cmd.id)` | `RenameSeason` |
| `BlockCommandsImpl` | 1 | `find_by_id(cmd.id)` | `UpdateBlockTimeSpan` |
| `EpisodeCommandsImpl` | 1 | `find_by_id(cmd.id)` | `RenameEpisode` |
| `SceneCommandsImpl` | 11 | scene/episode/shooting_day → series (1–2 hop) | `CreateScene`, `UpdateSceneDetails`, `AssignCharacter`, `RemoveCharacter`, `ScheduleSceneOnShootingDay`, `UnscheduleSceneFromShootingDay` |
| `ShootingDayCommandsImpl` | 11 | shooting_day/episode → series (1–2 hop) | `CreateShootingDay`, `RenameShootingDay`, `RescheduleShootingDay`, `ReorderShootingDay`, `ArchiveShootingDay`, `WrapShootingDay` |
| `CharacterCommandsImpl` | 5 | character/season → series (1–2 hop) | `CreateCharacter`, `UpdateMeasurements`, `UpdateContactInfo` |
| `CostumeCommandsImpl` | 20 | costume → character → season → series (2–3 hop) | `CreateCostume`, `UpdateCostumeNotes`, `AssignCostumeToCharacter`, `UnassignCostume`, `AddDetail`, `RemoveDetail`, `LinkPhoto`, `UnlinkPhoto` |
| `CostumeCategoryCommandsImpl` | 7 | category/season → series (1–2 hop) | `CreateCostumeCategory`, `RenameCostumeCategory`, `ReorderCostumeCategory`, `ArchiveCostumeCategory` |
| `PhotoCommandsImpl` | 10 | binding → costume/continuity → … series (3–5 hop) | `UploadPhoto`, `NormalizeOriginal`, `GenerateVariant`, `MarkVariantFailed`, `DeletePhoto` |
| `SceneShootCommandsImpl` | 32 | scene_shoot → scene → episode → series (2–3 hop) | `PlanSceneShoot`, `ReplanSceneShoot`, `StartSceneShoot`, `SetActualOrder`, `FinishSceneShoot`, `SkipSceneShoot`, `AddSceneShootNote`, `UpdateSceneShootNote`, `RemoveSceneShootNote`, `LinkContinuityPhoto`, `UnlinkContinuityPhoto` |

**Already migrated (reference):** `MembershipCommandsImpl` + 6 membership
commands (commit `1ebb97a`). Membership uses plain `SeriesId`; **the 46 new
fields use `Option<SeriesId>`** per the issue's design note (e.g. `CreateCostume`
can be created without a parent → genuinely unknown at creation).

## 3. Migration pattern (per adapter)

Follow the `MembershipCommandsImpl` precedent exactly:

1. **`crates/core/src/<aggregate>/commands.rs`** — add
   `pub series_id: Option<SeriesId>` to each command struct lacking it; add
   `SeriesId` to the `use crate::shared::{…}` import. Doc-comment each field
   with the audit-trail rationale (same wording as membership).

2. **`crates/infra/src/event_store/command_adapters.rs`** — in the adapter's
   `impl` block:
   - Delete the repo fields that were only used for `series_id` resolution
     (all of them are; verify per adapter), drop them from `new(...)`,
     `Self { … }`, and the struct definition.
   - Replace the `find_by_id` resolution block with `let series_id = cmd.series_id;`.
   - Delete `PhotoCommandsImpl::resolve_series_id_for_binding` entirely.

3. **`crates/api/src/handlers/mod.rs`** — resolve `series_id` *before*
   constructing the command, via the appropriate `state.ports.<x>_repo()
   .find_by_id(..).await.map_err(map_err)?.series_id`. For `create_*`
   handlers whose request body already carries `series_id`, use `req.series_id`.
   Multi-hop chains (costume, scene_shoot, photo) use private helpers defined
   once in `handlers/mod.rs` (see §4) to avoid 8–11 inline copies.

4. **`crates/infra/src/sagas/` + `crates/infra/src/photo/sagas/`** — sagas
   already resolve `series_id` for their own `EventMetadata`; pass that value
   into the command struct as `series_id` (the value is already
   `Option<SeriesId>`).

5. **`crates/api/src/main.rs`** — drop the now-unused repo arguments from each
   `*CommandsImpl::new(...)` call.

6. **Tests** — add `series_id: Some(SeriesId::new())` (or `None` where a
   command genuinely has no parent) to command constructors in:
   - `crates/core/tests/*_aggregate.rs` (10 files)
   - `crates/integration-tests/tests/*.rs` (round-trip + adapter + repo tests)
   - `crates/api/tests/common/mod.rs` — fake repos must return stub views
     (FakeBlockRepo precedent) so handler-level `series_id` resolution succeeds.
   - `crates/fuzz-targets/fuzz_targets/*.rs` (3 files: create_scene,
     create_character, shooting_day_member)
   - `crates/api/src/handlers/test_helpers.rs` — **dead file** (not wired via
     `mod`); verify it is not compiled before deciding to touch it.

## 4. Handler resolution helpers (new private fns in `handlers/mod.rs`)

Return `Result<SeriesId, (StatusCode, Json<ErrorResponse>)>` so callers use
`map_err(map_err)?`-style `?`:

```rust
/// Scene → Episode → series (2-hop).
async fn series_id_for_scene<P: Ports>(
    state: &AppState<P>, scene_id: Uuid,
) -> Result<SeriesId, (StatusCode, Json<ErrorResponse>)> { … }

/// SceneShoot → Scene → Episode → series (3-hop).
async fn series_id_for_scene_shoot<P: Ports>(
    state: &AppState<P>, shoot_id: SceneShootId,
) -> Result<SeriesId, (StatusCode, Json<ErrorResponse>)> { … }

/// Costume → Character(opt) → Season → series (2–3 hop).
/// Returns `Ok(None)` when the costume is unassigned (mirrors adapter semantics);
/// hard-404s when the costume itself is missing.
async fn series_id_for_costume<P: Ports>(
    state: &AppState<P>, costume_id: Uuid,
) -> Result<Option<SeriesId>, (StatusCode, Json<ErrorResponse>)> { … }
```

## 5. Wave staging (separate commits)

Follow the issue's staging — never one mega-commit:

1. **Wave 1 — Season / Block / Episode** (3 structs, ~3 handlers): simplest,
   1-hop, state carries `series_id`.
2. **Wave 2 — Character / CostumeCategory / Scene / ShootingDay** (19 structs).
3. **Wave 3 — Costume / SceneShoot** (19 structs, 3-hop chains).
4. **Wave 4 — Photo** (5 structs, binding-dispatched; sagas reuse their
   `resolve_series_id` helpers).

Each wave: core structs + adapters + handlers (+ helpers) + sagas + tests +
fuzz targets + header updates, then `cargo fmt`, `cargo build --workspace`,
`cargo clippy --workspace --all-targets -D warnings`, `cargo test -p core`,
`cargo test -p api --tests`.

## 6. Behavioral notes / pitfalls

- **`CreateCostume`** has no parent → handler passes `series_id: None`.
- **`UploadPhoto`**: handler already resolves costume → character → season for
  the AUTHZ-GATE; reuse that chain + `season_repo.find_by_id(season_id)` for
  the series. Unassigned costume → 400 (existing AUTHZ behavior) → series
  always resolvable when the command is dispatched.
- **Continuity photo handlers** (`link/unlink_continuity_photo`) already walk
  `shooting_day → episode → block` for authz; `BlockView.series_id` is
  available — reuse it instead of a second chain.
- **`update_shooting_day` / `update_costume_category`** dispatch one of two
  commands in branches — resolve `series_id` once before the branch.
- **Adapters must stay best-effort-free**: after the migration they perform
  zero projection reads. Do not reintroduce `.ok()`-wrapped lookups.
- **`schedule_on_shooting_day` / `unschedule_from_shooting_day`** currently
  hard-`?` on `shooting_day_repo.find_by_id`; the handler replicates that
  existence check (404) at the API edge.
- **Sagas pass `series_id` into the command** but keep their own
  `resolve_series_id` for `EventMetadata` — do not remove saga helpers.

## 7. SPDX headers

`// Co-authored-by: deepseek-v4-flash (opencode-go)` (from `$PI_MODEL`
`$PI_PROVIDER`) must be added under the Copyright line of every touched file
that lacks it, per AGENTS.md §7. Affected files missing it today:
`core/src/{season,block,episode,scene,character,costume,costume_category}/commands.rs`,
`infra/src/event_store/command_adapters.rs` (has `hy3`, `glm-5.2` — append),
sagas, `api/tests/common/mod.rs`, core/integration/fuzz test files.

## 8. Verification checklist

- [x] `cargo build --workspace` clean
- [x] `cargo clippy --workspace --all-targets -- -D warnings` clean
- [x] `cargo test -p core` (all aggregate tests green)
- [x] `cargo test -p api --tests` (handler tests green)
- [x] `cargo test -p integration-tests -- projector_tests` (Tier 1–3)
- [x] `cargo test -p integration-tests -- sierradb_round_trip` (Tier 4)
- [x] `grep -rn "find_by_id" crates/infra/src/event_store/command_adapters.rs` → **0 matches**
- [x] `cargo test -p architecture_tests` (boundary rules intact)
