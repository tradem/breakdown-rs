## Why

The single `ProjectId` value type is overloaded: today it means *work-unit scope* (Scene/Calculation), *production scope* (Characters), *authorization scope* (planned Membership), and is even carried by Costumes that should be scope-free. Stakeholder input on the actual production hierarchy — a *Series* containing *Seasons*, *Blocks* (which group episodes and are the natural rotation boundary for costume-department staff), and *Episodes* — exposes that `ProjectId` conflates four different scopes that must be modeled distinctly before the membership/authorization work lands. We are pre-production (no historical events in SierraDB), so this is the cheapest possible window for a schema-breaking refactor.

## What Changes

- **BREAKING** Introduce a four-level production hierarchy: `Series` (opaque `SeriesId`, no aggregate yet) → `Season` (aggregate) → `Block` (aggregate) → `Episode` (aggregate).
- **BREAKING** `Season.number`, `Block.number`, and `Episode.number` are all **series-global running counters** (not scoped to their parent), enforced via Postgres unique indexes on `(series_id, number)`.
- **NEW** `Block` carries optional `start_date` / `end_date: Option<NaiveDate>` (always a real-world time span, but not enforced as filled).
- **BREAKING** `Scene`: rename `project_id` → `episode_id`; a Scene is scoped to exactly one Episode.
- **BREAKING** `Character`: replace `is_main_character: bool` / `is_extra: bool` with a single `category: CharacterCategory` enum (`MainCast | Guest | Extra`); Characters are **season-scoped** (a Character references `season_id`); `appearances` (which Episodes a Character plays in) are **derived** from Scene→Character assignments in the read model, not stored as a redundant vector on the aggregate. Measurements and contact info remain on the Character (no separate `Actor` aggregate in v1 — deferred as an additive, non-breaking future change).
- **BREAKING** `Costume`: remove `project_id` entirely; a Costume references only `character_id: Option<Uuid>`. Costumes are **scope-free** (owned by the Character they dress, not by any production level), so they are not re-created per Episode/Block.
- **BREAKING** Remove the `calculation` Bounded Context entirely (core + infra + api + migrations + tests). The stakeholder confirmed calculations are out of scope for v1; keeping it would mean refactoring dead, requirement-less code. It can be reintroduced as a fresh capability when real requirements emerge.
- **BREAKING** Introduce `SeriesId` as an opaque UUIDv7 value type in `crates/core/src/shared.rs` (mirroring the existing `ProjectId`/`AggregateVersion` pattern). No `Series` aggregate in this change; `SeriesId` is the seam for an additive future `Series` aggregate (multi-show deployments are "currently not, but conceivable in future").

## Capabilities

### New Capabilities
- `production-hierarchy`: `SeriesId` opaque value type; `Season`, `Block`, `Episode` aggregates (state, commands, events) and their series-global numbering invariant; Block time span.
- `scene-scoping`: Scene's `episode_id` scoping (replaces `project_id`) and membership of a Scene in exactly one Episode.
- `character-modeling`: Character `category` enum, season-scoping (`season_id`), and the derived (read-model-only) appearances model; removal of the legacy bool flags.
- `costume-character-binding`: Costume's scope-free design — bound only to a `character_id`, no production-level scope.

### Modified Capabilities
<!-- The existing domain contexts (scene/character/costume) have no committed specs in openspec/specs/ yet, so they are introduced fresh by the "New Capabilities" above rather than modified. The calculation context is removed wholesale (no spec to modify — it was uncommitted). -->

## Impact

- **crates/core**: new `season/`, `block/`, `episode/` modules (aggregate/commands/events/error/ports/views); new `SeriesId` in `shared.rs`; modify `scene/`, `character/`, `costume/` events+commands+aggregates+ports+views; **delete `calculation/`**.
- **crates/infra**: new projectors + queries + migrations for Season/Block/Episode; modify scene/character/costume projectors, queries, command adapters, and migrations (project_id → episode_id / season_id / removed); **delete calculation projector/query/command-adapter/migrations**.
- **crates/api**: new handlers for Season/Block/Episode CRUD; update Scene/Character/Costume handlers and OpenAPI types; **delete calculation handlers + routes**.
- **crates/integration-tests**: update all Tier-1–4 fixtures and assertions referencing `project_id`; delete calculation tests; add Season/Block/Episode projector/round-trip tests.
- **OpenSpec cross-change**: the in-flight `add-oidc-auth-and-membership` change (0/46 tasks) is authored against `ProjectId`-scoped membership and **must be reformulated to `BlockId`-scoped membership** before implementation (separate revision to that change's specs).
- **Architecture tests**: update `rust_arkitect` boundary assertions if new modules are added to `crates/core/src/`.
- **Event-schema break**: this change is only cheap because we are pre-production; it must land before any real events are persisted in SierraDB.
