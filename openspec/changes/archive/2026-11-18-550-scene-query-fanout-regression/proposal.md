<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: qwen3.8-flash (opencode-go) -->

# Scene read-model fan-out fix (#550) — duplicated `assigned_characters` / `shooting_day_ids`

## Why

Issue #550: every `array_agg` in the scene/shooting-day read queries lacked
`DISTINCT` while joining independent one-to-many pivots
(`projection_scene_character` × `projection_scene_shooting_day`), so the
lists came back with one element **per multiplied row** (`c·d`, and `c·c·d`
in `scenes_by_character`, which joined the character pivot twice). The
projections themselves are correct (composite PKs rule out duplicate rows);
only the SELECT was wrong. The symptom surfaced client-side in
`scene_detail_screen.dart`: the header showed "Drehtage (2)" for one day
while the set-based picker filter found no candidate and permanently
disabled the schedule button.

**Drift check:** the fan-out was confirmed live in
`crates/infra/src/queries/scene.rs` (three queries) and
`crates/infra/src/queries/shooting_day.rs` (`scenes_by_shooting_day`) on the
current `main` — not previously fixed. The AI-import preview/apply screens
consume draft DTOs (no `assignedCharacters`/`shootingDayIds` rendering), so
no additional client dedup site exists there.

## What Changes

1. **Backend (the fix):** replace the multiply-joining shape with correlated
   scalar subqueries (`array_agg` scoped to a single pivot per scene) — the
   issue's recommended form that removes the row multiplication instead of
   masking it with `DISTINCT`. Applied consistently to all four affected
   entry points (`find_by_id`, `list_by_episode`, `scenes_by_character`,
   `scenes_by_shooting_day`); the filter-only joins become `WHERE EXISTS`
   (`scenes_by_character`'s double join included). No migration, no
   projector change — read-only.
2. **Backend (tests):**
   `crates/integration-tests/tests/scene_query_fanout_regression.rs` —
   Postgres-only Tier-1–3 suite with the fan-out-triggering fixture (2
   characters × 2 shooting days, the 1×1 case passed before and let the bug
   through): each of the four entry points must report exactly 2 + 2
   elements, plus an aggregate-vs-query cross-check that folds the same
   event stream through `Apply` and the production `SceneProjector`.
3. **Client (defensive, per the issue's decision — *not* the closure reason):**
   `scene_detail_screen.dart` dedups `assignedCharacters` and
   `shootingDayIds` before rendering count + rows + picker filter, and
   `scenes_widgets.dart` dedups the tile counts, so a future read-model
   regression degrades gracefully instead of producing a self-contradictory
   screen. Widget tests pin the invariant (duplicated ids → one row, honest
   count, picker still consistent).

## Impact

- No wire-format or `openapi.yaml` change (lists stay lists).
- No public Rust API change (`SceneRepository` / `ShootingDayRepository`
  ports untouched) → no crate version bumps.
- Array elements are now returned in a deterministic order (sorted by id);
  the old order was join-order-dependent and unspecified.
