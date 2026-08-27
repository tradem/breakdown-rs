## Why

Costume parts today are an unstructured `Vec<CostumeDetail { id, text }>`. Costume supervisors cannot filter "all shoes across the season" or group by part-type, and there is no shared vocabulary so synonymous free-text ("Schuhe" / "Schuh") drifts over time. The fix needs to be user-editable (not an enum — production vocabularies differ per show) and season-isolated (matching Breakdown's season-scoping posture), with a sensible default seed applied when a new Season appears.

## What Changes

- **Grow `CostumeDetail` from `{ id, text }` to `{ id, subject: Option<String>, category_id: Option<CostumeCategoryId>, text }`**. `subject` is a free-form per-detail micro-title ("Rote Lederjacke"); `category_id` references the new CostumeCategory aggregate. Both are optional. Existing `text` keeps its meaning (the description) and is **not** reinterpreted into `subject`.
- **Introduce a new `CostumeCategory` aggregate**, scoped to exactly one `Season` (consistent with `Character`, which is also Season-scoped). It carries:
  - `id: Uuid` (UUIDv7)
  - `season_id: SeasonId`
  - `name: String`
  - `order_key: LexicalSortKey` — reuses the shared VO introduced by the sibling `enrich-scene-with-shooting-day` change
  - `archived: bool` — soft-archive (standing rule for cross-aggregate references in this codebase)
  - `version: AggregateVersion`
- **The category catalog is season-local to Costume**: because `Costume` is scope-free (bound only to `character_id`), a Costume without a character assignment has no Season and therefore cannot yet be categorised. Categorisation becomes meaningful once a Costume is assigned to a Season's character; `category_id` stays `None` until then — this is acceptable and by design.
- **Configurable default seeding**: a new projector-driven **saga** subscribes to `SeasonCreated` events and issues `CreateCostumeCategory` commands for each entry of a configurable default seed set (default: Oberteil, Unterteil, Schuhe, Jacke, Accessoires). The seed source is configurable (toml/env), not hardcoded. The saga is idempotent (replay-safe) via a "have I seeded this season?" guard keyed on `season_id`.
- **Soft-archive cross-aggregate integrity**: deleting a `CostumeCategory` is forbidden while any `CostumeDetail` references it (validated against the read model at command time is avoided for purity — instead, archive is terminal like ShootingDay: only `ArchiveCostumeCategory` exists; historical costume-detail references survive, the picker hides archived categories). Renaming propagates via a new projector subscription: the costume projection subscribes to the `costume_category` stream and refreshes the denormalised `category_name` column on `CostumeCategoryRenamed`.
- **Projection updates**: `projection_costume_detail` gains `subject TEXT`, `category_id UUID`, `category_name TEXT` (denormalised); new `projection_costume_category` table (season-scoped, ordered by `order_key`); new projector on the `costume_category` stream updating both `projection_costume_category` and the denormalised `projection_costume_detail.category_name`.

Not in scope: outfit-level categorisation (tagging the *whole* costume), a global cross-season category vocabulary, migration of existing `text` into `subject`, an admin UI for editing the seed.

## Capabilities

### New Capabilities
- `costume-category`: The `CostumeCategory` aggregate (season-scoped, user-editable), the configurable default-seed saga reacting to `SeasonCreated`, the soft-archive cross-aggregate rule, rename-propagation projector, and the `CostumeDetail` categorisation slots (`subject`, `category_id`) with their projection columns.

### Modified Capabilities
_(None — the existing `costume-character-binding` requirements concern scope-free-ness, which is preserved unchanged. Categorisation is additive consumer-side behavior and is captured under the new `costume-category` capability above.)_

## Impact

- **`crates/core/src/costume/`** — `events::CostumeDetail` grows `subject`/`category_id`; `views::CostumeDetailView` grows `subject`/`category_id`/`category_name`; commands unchanged structurally (existing `AddDetail` carries the enriched `CostumeDetail`).
- **`crates/core/src/costume_category/`** (new module) — aggregate, commands, events, views, error, ports.
- **`crates/core/src/shared.rs`** — new `CostumeCategoryId(Uuid)` (consumes `LexicalSortKey` from the sibling change).
- **`crates/infra`** — `CostumeCategoryCommands`/`CostumeCategoryRepository` adapters; new `CostumeCategoryPostgresProcessor` subscribing to `costume_category`; existing costume projector extended to maintain `category_name` by re-subscribing (or receiving rename events); migration adding columns + `projection_costume_category`.
- **Sagas**: introduces the canonical "projector-issues-commands" mechanism — a `SeasonCreated` subscriber that dispatches `CreateCostumeCategory`. This is a new architectural pattern for Breakdown RS and will be reused by the future AI-imported ShootingDay flow.
- **`crates/api`** — routes for `CostumeCategory` CRUD scoped to a Season; `AddDetail`/`UpdateDetail` accept the new slots.
- **`crates/integration-tests`** — Tier-4 coverage for the seeding saga, rename propagation, and_archive keeping historical references.

## Ordering note (sibling change dependency)

This change reuses `LexicalSortKey` introduced by the sibling change
`enrich-scene-with-shooting-day`. Either may be implemented first; whichever
lands first adds `LexicalSortKey` to `core/src/shared.rs`, the second consumes it.
The two changes are otherwise independent and may be reviewed/landed in either order.
