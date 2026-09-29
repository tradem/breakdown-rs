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
`Character` and `Costume` are scoped to a `Season` (`Character.season_id`) / scope-free (`Costume` is bound only via cross-aggregate references: `character_id` and, since #543, the optional `category_id` — both season-scoped aggregates, resolved by join in the read model).
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
that classifies **costumes** (n:1 per costume, optional — issue #543; e.g. Oberteil/Unterteil/Schuhe). It carries `season_id`, `name`, a
`LexicalSortKey` order_key, an `archived` flag, and a version. Seeding is a projector-driven **saga**:
on every `SeasonCreated` the `SeasonSeedingSaga` dispatches `CreateCostumeCategory` for the season's
default categories (config `config/default_costume_categories.toml`), guarded by
`CostumeCategoryRepository::count_for_season` so replays never double-seed. The costume's category is set
cleared via `SetCostumeCategory` (`CostumeCategorySet`; `None` clears) — the season invariant
(`category.season_id ∈ repertoire ∪ season(character)`) is pre-checked at the API edge (409
`costume-category.season-mismatch`). Legacy `CostumeDetail.category_id` values derive the costume category
on replay via the first-wins rule (first detail category in event order, within one event `detail_id` ASC),
executed identically by `CostumeAggregate::apply` and the costume projector; details are pure description
(`subject` + `text`) on the wire. The costume projector resolves `category_name` best-effort at write time;
rename propagation targets `projection_costume.category_name`. The command API lives at
`POST/GET /seasons/{season_id}/costume-categories` (and `PATCH`/`POST .../archive` by id) plus
`POST /costumes/{id}/category` (issue #543); `POST /costumes/{id}/details` accepts a pure-description
`CostumeDetailRequest`, and `PATCH`/`DELETE /costumes/{id}/details/{detail_id}` edit and remove a detail
(issue #544, body = the costume aggregate's `VersionRequest` echo; an unknown `detail_id` answers 404
`costume-detail.not-found`, a distinct code from `costume.validation` so a client can tell a stale row
apart from a validation failure). `DetailUpdated` carries the **full** detail, not a patch, and the
projector reuses the `DetailAdded` upsert (no migration). Both detail routes are handler-internal
`AUTHZ-GATE`s over `authorize_costume_scoped`, like the photo handlers and `POST /costumes/{id}/category`.

