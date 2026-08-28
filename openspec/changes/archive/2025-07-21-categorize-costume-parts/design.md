# Design — categorize-costume-parts

## Locked decisions (from explore session)

1. **Categorisation lives on the part (`CostumeDetail`), not the outfit.** Categories
   like Oberteil / Unterteil / Schuhe / Jacke / Accessoires are *part* types; a
   costume is composed of several. An outfit-level categorisation is explicitly
   out of scope.
2. **The catalog is a `CostumeCategory` aggregate scoped to a `Season`** (matching
   `Character`, which is also Season-scoped). Not global, not per-Costume.
3. **`subject` and `category_id` are orthogonal.** `subject` is a free-form
   per-detail micro-title ("Rote Lederjacke"); `category_id` is the shared
   vocabulary slot.
4. **User-editable, not an enum.** The `CharacterCategory` enum pattern
   (`character/category.rs`) does **not** apply here — categories must be
   extendible per-season by production staff.
5. **Default seed is configurable** (toml/env), not hardcoded constants.
6. **Soft-archive is the cross-aggregate integrity rule** (same as ShootingDay in
   the sibling change). Hard-delete does not exist.
7. **Rename propagation is event-driven via a projector subscription**, the
   canonical ES answer for denormalised labels.
8. **A projector-issues-commands saga seeds defaults on `SeasonCreated`.** This
   is a new architectural pattern for Breakdown RS and the precedent for the
   future AI-imported ShootingDay flow.

## Why season-scoped (not global)

The project's posture is season isolation: every hierarchy entity plus Character
is season-scoped. A global mutable vocabulary crosses that boundary and raises
governance questions (who can edit? whose productions are affected?). A
season-scoped catalog isolates the vocabulary per production and lets season
staff edit freely.

The cost: a `Costume` that is not yet bound to a `Character` has no Season, so
`category_id` must stay `None` until assignment. This is acceptable — categorising
parts before you know which season's vocabulary applies is meaningless. The
`costume-character-binding` requirement "Costume is scope-free" stays untouched;
the Costume aggregate never gains a Season field.

## Module layout

```
crates/core/src/
├── shared.rs                           + CostumeCategoryId(Uuid); consumes LexicalSortKey
├── costume/
│   ├── events.rs        CostumeDetail { id, subject?, category_id?, text }
│   ├── views.rs         CostumeDetailView { id, subject?, category_id?, category_name?, text }
│   ├── commands.rs      AddDetail / RemoveDetail unchanged structurally (carry enriched CostumeDetail)
│   └── aggregate.rs     unchanged shape — CostumeDetail is opaque to the aggregate
└── costume_category/                   (new)
    ├── mod.rs
    ├── aggregate.rs     CostumeCategoryAggregate { id, season_id, name, order_key, archived, version }
    ├── commands.rs      CreateCostumeCategory, RenameCostumeCategory, ReorderCostumeCategory, ArchiveCostumeCategory
    ├── events.rs        Created / Renamed / Reordered / Archived
    ├── views.rs         CostumeCategoryView
    ├── error.rs         CostumeCategoryError (incl. ArchivedCannotBeMutated, DuplicateName)
    └── ports.rs        CostumeCategoryCommands, CostumeCategoryRepository + SeasonSeedingPort (read check)
```

## CostumeCategory aggregate

```text
CostumeCategoryAggregate {
    id: Uuid,
    season_id: SeasonId,
    name: String,
    order_key: LexicalSortKey,
    archived: bool,
    version: AggregateVersion,
}
```

| Command | Event | Notes |
|---|---|---|
| `CreateCostumeCategory { id, season_id, name, order_key }` | `CostumeCategoryCreated` | New stream. `name` non-empty; `order_key` validated. |
| `RenameCostumeCategory { id, name, version }` | `CostumeCategoryRenamed` | Changes `name` only. |
| `ReorderCostumeCategory { id, order_key, version }` | `CostumeCategoryReordered` | Single-key move; one event. |
| `ArchiveCostumeCategory { id, version }` | `CostumeCategoryArchived` | Soft delete, terminal. |
| *(no unarchive)* | — | One-way; historical references survive. |

`CreateCostumeCategory` does **not** enforce name-uniqueness within a season in
the aggregate (would require a projection lookup, violating purity). Uniqueness
is a read-model/UX concern surfaced to the user at creation time; duplicates in
the event log are tolerated. (If hard uniqueness is later required, it becomes a
saga-time validation, not an aggregate invariant.)

Mutation commands reject with `ArchivedCannotBeMutated` when `archived` is `true`.

## CostumeDetail enrichment

```text
CostumeDetail {
    id: Uuid,
    subject: Option<String>,            // free-form micro-title
    category_id: Option<CostumeCategoryId>,  // references CostumeCategory
    text: String,                      // the description (unchanged meaning)
}
```

- `AddDetail` command already carries a `CostumeDetail`; it transparently
  accepts the enriched shape. No new event variant is required — `DetailAdded`
  carries the (now larger) `CostumeDetail` value.
- Existing persisted `DetailAdded` events (pre-production; safe to discard if
  needed) deserialize with `subject: None`, `category_id: None` via serde
  defaults. **No `text` → `subject` migration** — they are distinct semantics.
- `CostumeDetailView` adds `subject` and `category_id` plus a denormalised
  `category_name: Option<String>` for read convenience.

No existence check against `CostumeCategory` is performed in the costume command
path (aggregate isolation). The read model joins to resolve `category_name`; a
dangling `category_id` renders as `category_name = None`. With soft-archive as
the only removal path, dangling references cannot occur in practice.

## Configurable default seeding (the saga)

```
                          SeasonCreated event
                                  │
                  ┌───────────────▼────────────────┐
                  │ SeasonSeedingSaga               │  (new subscriber)
                  │  1. guard: already seeded?      │
                  │     (CostumeCategoryRepository  │
                  │      ::exists_for_season)        │
                  │  2. load seed config (toml/env)  │
                  │  3. for each entry: dispatch     │
                  │     CreateCostumeCategory with   │
                  │     a generated order_key        │
                  └─────────────────────────────────┘
```

- **Source of seed**: a toml file (`config/default_costume_categories.toml`)
  overridable by env var (`DEFAULT_COSTUME_CATEGORIES`), parsed in `infra` (not
  `core` — keeps `core` infra-free). v1 default content: Oberteil, Unterteil,
  Schuhe, Jacke, Accessoires.
- **Idempotency guard** (replay-safety): before dispatching, the saga queries
  `CostumeCategoryRepository::count_for_season(season_id)`; if > 0, skip. This
  makes reprocessing `SeasonCreated` events on projector restart safe.
- **Order keys**: the saga generates initial keys using a monotonic sequence
  (`"a"`, `"b"`, …) — there is no concurrent insertion during seeding, so simple
  sequential keys suffice for the seed.
- **Pattern precedent**: this is the canonical "event-reactor-issues-commands"
  mechanism; the future AI-imported ShootingDay flow will reuse the same shape.

## Rename propagation (the other projector)

```
CostumeCategoryRenamed event
        │
        ▼
CostumeCategoryPostgresProcessor (subscribes to costume_category stream)
   1. upsert projection_costume_category
   2. UPDATE projection_costume_detail
      SET category_name = new_name
      WHERE category_id = renamed.id
```

On `CostumeCategoryRenamed`, the projector updates both the category table and
the denormalised `category_name` on every referencing costume detail. This is a
plain SQL `UPDATE ... WHERE category_id = $1` — no fan-out commands, no
event-stream touch on the Costume aggregate.

For `CostumeCategoryArchived`, the projector sets `archived = true` on
`projection_costume_category`; existing references in `projection_costume_detail`
keep their (now archived) `category_name` so historical costume views still read
coherently.

## Projection schema (migration)

```sql
ALTER TABLE projection_costume_detail
    ADD COLUMN subject       TEXT,
    ADD COLUMN category_id    UUID,
    ADD COLUMN category_name  TEXT;   -- denormalised; refreshed by costume_category projector

CREATE TABLE projection_costume_category (
    id          UUID PRIMARY KEY,
    season_id   UUID NOT NULL,
    name        TEXT NOT NULL,
    order_key   TEXT NOT NULL,
    archived    BOOLEAN NOT NULL DEFAULT false,
    version     BIGINT NOT NULL,
    updated_at  TIMESTAMPTZ NOT NULL
);
CREATE INDEX idx_projection_costume_category_season
    ON projection_costume_category(season_id, order_key);
```

## Testing strategy

- **Core unit tests** (`costume_category/aggregate_test.rs`): creation, rename,
  reorder-midpoint (single event, siblings untouched — shared `LexicalSortKey`
  test), archive is terminal + rejects mutations, version-mismatch rejection.
- **Costume unit tests**: `AddDetail` accepts enriched `CostumeDetail`, idempotent
  push on duplicate `detail.id`, `RemoveDetail` removes by id, `CostumeDetailView`
  serialises the new slots.
- **Saga idempotency test** (infra-layer, Test-double `SeasonSeedingPort`): replay
  the same `SeasonCreated` twice → exactly N `CreateCostumeCategory` commands
  issued once (guard skips the second pass).
- **Mutation surface**: the archived-guard and the saga idempotency guard are
  prime mutation targets — kill-tested explicitly.
- **Integration (Tier 4)**: season created → saga seeds defaults →
  `CostumeCategoryRepository::list_by_season` returns the seed in `order_key`
  order; rename a category → `projection_costume_detail.category_name` refreshed;
  archive a referenced category → historical costume view still shows the name;
  create a costume, assign to character, add a categorized detail → join resolves
  `category_name`.

## Out of scope (explicitly)

- Outfit-level categorisation / tagging the whole costume.
- A global cross-season category vocabulary.
- Migration of existing `text` values into `subject`.
- An admin UI for editing the seed config (only the config-loading mechanism).
- Hard name-uniqueness enforcement at the aggregate level.
