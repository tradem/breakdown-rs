---
description: Domain model - hierarchy, aggregates and invariants (long form from former AGENTS.md section 2).
applyTo:
  - "crates/core/src/**"
  - "crates/infra/src/**"
  - "crates/api/src/**"
---

<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3 (neuralwatt) -->

# Production hierarchy (ADR: introduce-season-block-episode-hierarchy)

The domain models a four-level production hierarchy:
`Series` (opaque `SeriesId` only — no aggregate yet) → `Season` → `Block` → `Episode` → `Scene`.
`Character` and `Costume` are scoped to a `Season` (`Character.season_id`) / scope-free (`Costume` is bound only to a `Character`).
Core modules: `season`, `block`, `episode`, `scene`, `scene_shoot`, `shooting_day`, `character`, `costume`, `costume_category`, `shared`.
The `calculation` context was removed; do not reintroduce it.
`shooting_day` is an Episode-scoped `Drehtag` aggregate. It carries a `label`, a `LexicalSortKey`
fractional-ordering value (`shared`), an optional `date`, a `ShootingDaySource` provenance
discriminator (Manual | AiExtracted), an `archived` flag, and an optional `wrapped_at: Option<DateTime<Utc>>`.
`wrapped_at` is set idempotently by the `WrapShootingDay` command and indicates the day has been
"closed" for planning — the Soll-Ist report exposes this as the `final` flag. Scenes link to
ShootingDays via a many-to-many join (`Scene.schedule_on_shooting_day`) kept on the Scene
aggregate; the read model mirrors it in `projection_scene_shooting_day`. Archived days are
excluded from the picker query `ShootingDayRepository::list_by_episode`.
`scene_shoot` is a Scene-scoped execution-tracking aggregate (category `"scene_shoot"`).
Each `SceneShoot` represents one planned execution of a Scene on a ShootingDay, tracked
by `planned_order` (Soll) and `actual_order` (Ist). Lifecycle: `Planned` → `Scheduled` →
`InProgress` → `Shot` or `Skipped`. Key invariants: pair-uniqueness `(scene_id, shooting_day_id)`,
`planned_order` freezes after execution data is recorded (`PlannedOrderFrozen`), notes are
append-only with mutable bodies (`SceneShootNote`), and continuity photos link via
`ContinuityPhotoLinked/Unlinked` events. Three idempotent read-side reports are served from
`SceneShootReportRepository`: Dispo (planned_order ASC), Shoot Day (actual_order NULLS LAST),
and Soll-Ist (diff with moved/missing/skipped/reshot flags + `final` from `wrapped_at`).
The projector uses version guards (`WHERE version < $N`) to ensure event-redelivery idempotency.
`SeriesId` is an opaque UUIDv7 seam for a future additive `Series` aggregate — hierarchy entities reference it but no `Series` aggregate exists yet.
`costume_category` is a **season-scoped vocabulary** aggregate (`CostumeCategory`, category `"costume_category"`)
that classifies costume parts (e.g. Oberteil/Unterteil/Schuhe). It carries `season_id`, `name`, a
`LexicalSortKey` order_key, an `archived` flag, and a version. Seeding is a projector-driven **saga**:
on every `SeasonCreated` the `SeasonSeedingSaga` dispatches `CreateCostumeCategory` for the season's
default categories (config `config/default_costume_categories.toml`), guarded by
`CostumeCategoryRepository::count_for_season` so replays never double-seed. `CostumeDetail` is
enriched with optional `subject` and `category_id`; the costume projector resolves `category_name`
from `projection_costume_category` at read time. The command API lives at
`POST/GET /seasons/{season_id}/costume-categories` (and `PATCH`/`POST .../archive` by id);
`POST /costumes/{id}/details` now accepts the enriched `CostumeDetail`.

