<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3 (neuralwatt) -->

# 453 — Costume season repertoire: make unassigned costumes visible

## Why

`list_by_season` (`crates/infra/src/queries/costume.rs`) scopes the season
costume stream with an INNER JOIN through `projection_character`. A costume
created via `POST /v1/costumes` (empty body → `character_id = NULL`) never
appears in any season's stream, so there is no UI path to a costume's **first**
assignment. The Flutter widget contract (`assign-costume-<id>-none` row keys,
#368 harness) assumes unassigned costumes ARE visible.

## Decision (user-confirmed in session)

**Option 3 — Repertoire join table.** Main characters reuse costumes across
seasons, so neither an immutable `season_id` on the costume (option 1) nor a
global wardrobe pool (option 2) fits. Instead:

- A costume can be *in repertoire* for **several seasons** via a new
  `projection_costume_season (costume_id, season_id)` join table.
- `CreateCostume` accepts an optional `season_id` (the procurement/repertoire
  season). The API edge resolves `series_id` from the season projection
  (404 on unknown season — same pattern as `create_character`).
- `CostumeCreated` carries `season_id: Option<Uuid>`; the projector writes the
  repertoire row. `#[serde(default)]` keeps old events replayable.
- `list_by_season` returns the union: costumes **assigned to** a character of
  the season **OR** **in repertoire** for the season. Unassigned seasonal
  costumes become visible; artificial single-season coupling is avoided.

## Changes

1. **core** (`crates/core/src/costume/`)
   - `commands.rs`: `CreateCostume { season_id: Option<SeasonId>, … }`
     (replaces the `series_id: Option<SeriesId>` field — the season is the
     input, `series_id` is resolved at the edge for audit metadata).
   - `events.rs`: `CostumeCreated { season_id: Option<Uuid>, … #[serde(default)] }`.
   - `aggregate.rs`: emit `season_id` through to the event.
2. **infra**
   - Migration `20260216000001_costume_season_repertoire`:
     `projection_costume_season` join table + index.
   - `projectors/costume.rs`: insert/delete repertoire rows on
     `CostumeCreated`; carry `series_id` audit passthrough if applicable.
   - `queries/costume.rs`: `list_by_season` via `LEFT JOIN` + repertoire union.
   - `event_store/command_adapters.rs`: adapt `CreateCostume`.
3. **api**
   - `CreateCostumeRequest { season_id: Option<Uuid> }` (replaces empty body).
   - `create_costume` handler: resolve `series_id` via `season_repo().find_by_id`
     (404 on unknown season); validate season exists (CQRS: fine at the edge).
4. **api contract**: `UPDATE_OPENAPI=1` regen of `backend/openapi.yaml`.
5. **flutter** (follow-up / alignment): seed helper `seedCostumeAssignment`
   can create the costume with `season_id` instead of pre-assigning; the
   `@pending` optimistic-overlay scenario un-pends once the client aligns.

## Acceptance criteria (from issue)

- [ ] Backend decision implemented: unassigned costumes are listed in the
      season stream via the repertoire join (issue option (a), refined to a
      many-to-many repertoire binding).
- [ ] `costume_assignment.feature` optimistic-overlay scenario un-pends and
      passes on device (harness from #368) — backend side must be verified by
      the Flutter follow-up; this change un-blocks it.
