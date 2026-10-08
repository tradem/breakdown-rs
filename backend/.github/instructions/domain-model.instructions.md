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
<!-- Co-authored-by: space-bunny-free (opencode-go) -->

# Production hierarchy (ADR: introduce-season-block-episode-hierarchy; strategy: ADR-035)

The domain models a four-level production hierarchy:
`Project` (opaque `ProjectId` only — no aggregate yet) → `Season` → `Block` → `Episode` → `Scene`.
**ADR-035** (issue #531) records the strategic direction for this chain and binds new work:
the container target is **`Project`** (a 1:1 rename of the `Series` term — it dissolves
together with the `Season` term, it is *not* a new level above it), and the container chain
**below** `Project` becomes production-kind-configurable in a later change. Its normative
boundary: authorization predicates are typed by the *authorization level*, never by a
production-form-specific container — **no new `*_in_season` predicate may be added**
(B2), and cross-aggregate uniqueness keys are prefixed with the tenant id, i.e. `project_id`
(B4 — satisfied). Read it before adding a container-scoped authorization predicate or a
uniqueness constraint.

**The rename is complete (issues #591 and #599, ADR-035 D1/S1).** `core::shared` exposes
`ProjectId` (no `SeriesId` alias — internal workspace crate, nothing out-of-tree to protect),
and the ast-grep rule `backend/rules/no-stale-series-id.yml` fails CI on any stale `SeriesId`
**or** on a `series_id` Rust identifier. Three layers, three rules — do not treat the rename
as one sweep:
- **Layer 1 — the Rust type.** Mechanical; no compatibility alias exists on purpose.
- **Layer 2 — persisted wire keys: `series_id`, permanently.** The store already holds events
  under `series_id`; a rename surfaces as a projector dying on deserialization (SQLSTATE 22,
  #37 dead-letter), not a compile error. Do **not** "fix" this with
  `#[serde(rename = "project_id", alias = "series_id")]`: it reads old events correctly but
  re-serializes them under a *different* key, and `projection_audit.event_key` is built from
  the **re-serialized** payload (`write_audit_row`), so every replay would silently duplicate
  every pre-rename audit row. This is the **only** surviving `series_id` in the system:
  `SeasonCreated`/`BlockCreated`/`EpisodeCreated` and `EventMetadata`. Regression test:
  `crates/integration-tests/tests/project_id_rename_replay.rs`.
- **Layer 3 — storage and wire: `project_id` (#599).** Projection columns
  (`projection_season/_block/_episode/_audit.project_id`, indexes
  `idx_projection_*_project_id` / `idx_projection_*_project_number` — migration
  `20261008000001`), the read-model views, the OpenAPI properties and the `?project_id=`
  query parameters. The `#[schema(rename = "series_id")]` / `#[param(rename = "series_id")]`
  pins #591 had to add are **removed** — `utoipa` derives the wire name from the Rust field
  again, so renaming a field renames the contract. ADR-021 needed no `/v2` window here: at
  the time of the change no client had ever been released against `/v1`, so the rename landed
  in place (ADR-035 B5 outcome).
`Character` is scoped to a `Season` (`Character.season_id`). `Costume` is **not**
scope-free: since #453 it carries a season **repertoire** (`projection_costume_season`,
PK `(costume_id, season_id)` — m:n by construction, the wardrobe lifecycle carries a costume
from one season into the next), seeded from `CostumeCreated.season_id` and made real
aggregate state by #534; it additionally references the optional `category_id` (#543),
resolved by join in the read model.
That union is the costume's **domain** scope: it decides which seasons list the costume,
which series/project it resolves to, and what the season-scoped reports are about.
Its **authorization** scope is a separate question and is *not* that union:
`authorize_costume_scoped` (`api/src/handlers/mod.rs:757`) still checks the season-typed
predicate per scope today, but ADR-035 B2/S2 moves that boundary up to the **project** — a
costume-department role in any active block of the owning project. #535 removes the
`…_in_season` call from the photo path (a deliberate widening); the repertoire then only
serves to resolve *which* project. Do not re-introduce a season-union authorization check,
and do not let the client deny on the season union — it would block flows the server permits.
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
and Soll-Ist (diff with moved/missing/skipped/reshot flags + `final` from `wrapped_at`). Since #571 the same port additionally serves two **aggregated** Soll-Ist reports — `season_soll_ist_report(SeasonId)` / `episode_soll_ist_report(EpisodeId)` at `GET /v1/seasons/{id}/report/soll-ist` (+ `/v1/episodes/{id}/...`) and their `.pdf` twins (`ReportKind::SeasonSollIst`/`EpisodeSollIst`, own Typst templates, never archivable). Rows are one per scene × non-archived shooting day within the scope (day id + label attached, ordered by day `order_key`); `is_final` and the day counts are server-derived (`≥1` non-archived day AND all wrapped; zero days ⇒ `200` empty, never vacuously final); authz reuses the day reports' handler-internal `has_active_costume_role_in_season` gate.
The projector uses version guards (`WHERE version < $N`) to ensure event-redelivery idempotency.
`season` is the production-scope aggregate (`SeasonAggregate`, category `"season"`). It carries `series_id`, `number` (series-global uniqueness, `idx_projection_season_series_number` as authoritative backstop + API-edge 409 pre-check + — since ADR-036 / issue #586 — an atomic write-boundary reservation claim on the synthetic `reservation-seasnum-{series}-{n}` stream, like all four migrated cross-aggregate invariants), an optional `title`, an `archived` flag, and a version. The archived season's reservation/stays-reserved semantics are unchanged: the claim simply keeps the key blocked (the reaper consumes it once the aggregate exists). Lifecycle (issue #533): `ArchiveSeason` (`POST /v1/seasons/{id}/archive`, `SeasonArchived`) is the **terminal** state — an archived season rejects `RenameSeason` with 409 `season.archived` (repeat archive is an idempotent-reject, same pattern as `costume_category`), while its **number stays reserved** (uniqueness untouched — the number is historical identity) and its **inventory (blocks/episodes/shooting days) stays readable** (no cascade by decision). The archive handler carries the season-scoped AUTHZ-GATE reusing the existing `has_active_costume_role_in_season` predicate (no new ADR-035-B2 disallowed `*_in_season` variant). Read model: `projection_season.archived` (migration `20261004000001`), `SeasonView.archived` on the wire, `list_seasons` defaults to excluding archived seasons with an explicit `include_archived` opt-in.
`ProjectId` is an opaque UUIDv7 seam for a future additive `Project` aggregate — hierarchy entities reference it but no `Project` aggregate exists yet.
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
Since #534 the repertoire is **real aggregate state** (`CostumeAggregate.seasons`, seeded from
`CostumeCreated.season_id`, legacy events replay to an empty list): `POST /costumes/{id}/seasons` and
`DELETE /costumes/{id}/seasons/{season_id}` dispatch `AddCostumeToSeason`/`RemoveCostumeFromSeason` —
both are state-based idempotent no-ops (no event on repeat/absent), gated handler-internally by an
AUTHZ-GATE on the **target** season (existing `has_active_costume_role_in_season`, no new
`*_in_season` predicate, ADR-035 B2), and pre-checked at the API edge for existence (404
`season.not-found`) and archived state (409 `season.archived`, #533 terminal semantics — an
archived season rejects all further repertoire mutations). `projection_costume_season` is now truly
m:n: the projector INSERTs on add and DELETEs on remove; `CostumeView.season_ids` carries the
repertoire on the wire.

