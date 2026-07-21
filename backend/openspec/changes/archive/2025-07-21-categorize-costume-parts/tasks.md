## 1. Shared value object

- [x] 1.1 Add `CostumeCategoryId(Uuid)` opaque UUIDv7 id to `core/src/shared.rs` (mirror `EpisodeId`); re-export. (Consumes `LexicalSortKey` from the sibling `enrich-scene-with-shooting-day` change; if that change hasn't landed yet, also add `LexicalSortKey` here per its shared design — the two must not duplicate-define.)

## 2. CostumeCategory aggregate (core)

- [x] 2.1 Create `crates/core/src/costume_category/` module (`mod.rs` + aggregate/commands/events/views/error/ports) mirroring `scene/` layout.
- [x] 2.2 Implement `events.rs`: `CostumeCategoryEvent` variants `Created`, `Renamed`, `Reordered`, `Archived`; implement `kameo_es::EventType`.
- [x] 2.3 Implement `commands.rs`: `CreateCostumeCategory { id, season_id, name, order_key }`, `RenameCostumeCategory { id, name, version }`, `ReorderCostumeCategory { id, order_key, version }`, `ArchiveCostumeCategory { id, version }`; derive `serde::Deserialize` + `utoipa::ToSchema`; implement `kameo_es::CommandName`.
- [x] 2.4 Implement `aggregate.rs`: `CostumeCategoryAggregate { id, season_id, name, order_key, archived, version }`; `Entity` impl `category = "costume_category"`; `Apply` impl for all four events; `Command` impls with version-mismatch + `ArchivedCannotBeMutated` guards.
- [x] 2.5 Implement `error.rs`: `CostumeCategoryError` (`ArchivedCannotBeMutated`, `ValidationError`); wire into `core/src/error.rs`.
- [x] 2.6 Implement `views.rs`: `CostumeCategoryView { id, season_id, name, order_key, archived, version, updated_at }` (+ `ToSchema`).
- [x] 2.7 Implement `ports.rs`: `CostumeCategoryCommands` + `CostumeCategoryRepository` (list-by-season-in-order-key, count-by-season for the saga idempotency guard, get-by-id).
- [x] 2.8 Write `aggregate_test.rs`: creation, rename-preserves-order, reorder-midpoint single-event, archive terminal + rejects mutations, version-mismatch rejection.

## 3. CostumeDetail enrichment (core)

- [x] 3.1 Extend `costume::events::CostumeDetail` with `subject: Option<String>` and `category_id: Option<CostumeCategoryId>` (additive; `#[serde(default)]` for back-compat).
- [x] 3.2 Extend `costume::views::CostumeDetailView` with `subject`, `category_id`, and denormalised `category_name: Option<String>`.
- [x] 3.3 Verify `AddDetail` / `RemoveDetail` commands and `DetailAdded` / `DetailRemoved` events carry the enriched detail unchanged structurally (no command-shape change).
- [x] 3.4 Add costume unit tests: `AddDetail` accepts enriched detail, `CostumeDetailView` serialises new slots, legacy event deserialises with `subject: None`/`category_id: None`.

## 4. Configurable default seed (infra + saga)

- [x] 4.1 Add `config/default_costume_categories.toml` with v1 default (Oberteil, Unterteil, Schuhe, Jacke, Accessoires); allow override via `DEFAULT_COSTUME_CATEGORIES` env var; parse in `infra` (not `core`).
- [x] 4.2 Implement `SeasonSeedingSaga` subscriber in `infra` subscribing to the `season` stream's `SeasonCreated` events: load seed config, idempotency guard via `CostumeCategoryRepository::count_for_season`, dispatch `CreateCostumeCategory` with sequential `order_key`s.
- [x] 4.3 Spawn the saga in `main.rs` alongside the projectors; wire `CostumeCategoryCommands` into the composition root.

## 5. Rename/archive propagation projector (infra)

- [x] 5.1 Implement `CostumeCategoryPostgresProcessor` subscribed to the `costume_category` stream: upsert `projection_costume_category` for all four event variants; on `CostumeCategoryRenamed`, run `UPDATE projection_costume_detail SET category_name = $1 WHERE category_id = $2`; on `CostumeCategoryArchived`, set `archived = true` without nulling existing detail references.
- [x] 5.2 Extend the existing costume projector's `DetailAdded`/`DetailRemoved` handlers to populate `subject`, `category_id`, and `category_name` (resolved by join at projection time).

## 6. Projection migration

- [x] 6.1 Author `crates/infra/migrations/<ts>_costume_category_and_detail_fields.up.sql` (+ `.down.sql`): `ALTER TABLE projection_costume_detail ADD COLUMN subject TEXT, ADD COLUMN category_id UUID, ADD COLUMN category_name TEXT`; create `projection_costume_category` (id, season_id, name, order_key, archived, version, updated_at) + index `(season_id, order_key)`.

## 7. API surface

- [x] 7.1 Add Axum routes for CostumeCategory CRUD scoped to a Season: `POST /seasons/:season_id/costume-categories`, `PATCH /costume-categories/:id` (rename/reorder), `POST /costume-categories/:id/archive`, `GET /seasons/:season_id/costume-categories` (list in order). Extend OpenAPI schemas.
- [x] 7.2 Ensure costume `AddDetail` request DTO accepts `subject`/`category_id`; return enriched `CostumeDetailView` in responses; document in swagger.

## 8. Integration tests (Tier 4)

- [x] 8.1 Seed: `SeasonCreated` → saga emits → `CostumeCategoryRepository::list_by_season` returns seed in `order_key` order; replay `SeasonCreated` does not double-seed.
- [x] 8.2 Rename propagation: rename a category → `projection_costume_detail.category_name` refreshed for all referencing rows after projector catches up.
- [x] 8.3 Archive preserves history: archive a referenced category → costume view still shows its `category_name`; archived day hidden from picker list.
- [x] 8.4 End-to-end costume categorisation: create costume → assign to character → add categorized detail (`category_id = C`) → read view resolves `category_name`.

## 9. Guardrails & docs

- [x] 9.1 Run `cargo test -p core`, `cargo test -p architecture_tests`, `cargo deny check bans`; ensure no `core → infra/api` leak and seed config parsing stays in `infra`.
- [x] 9.2 Run `cargo mutants --in-diff` on changed `core` modules; kill-test the archived-guard and any saga idempotency-guard survivors.
- [x] 9.3 Add SPDX headers to new `.rs`/`.sql`/`.toml` files via `./scripts/add-spdx-headers.sh crates/core/src/costume_category crates/infra/migrations config`.
- [x] 9.4 Note the new "projector-issues-commands saga" pattern in AGENTS.md (Section 1: Architecture & Core Patterns) as the canonical mechanism for event-reactor seeding — precedes the future AI-imported ShootingDay flow.
