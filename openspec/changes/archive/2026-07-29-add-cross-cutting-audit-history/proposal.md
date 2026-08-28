## Why

`projection_audit` exists today but covers only the `membership` aggregate ("v1 scope"). There is no cross-cutting, filterable, paginated history view over *all* domain events, and no auditable record of *who* performed each state change across the broader domain. A breakdown app with collaborative scheduling needs a full audit trail (actor + provenance + tenant scoping) for every aggregate's events — readable administratively and scoped per series/block. This change generalizes the existing audit projection to all 11 entity categories and introduces a single shared `EventMetadata` so the actor who triggered each event is captured at the source.

## What Changes

- Introduce a shared `core::shared::EventMetadata { actor: Option<UserId>, provenance: Provenance, series_id: Option<SeriesId> }` type with `Provenance { Human | Saga(&'static str) | System }`, replacing the membership-only `MembershipMetadata` and the `()` metadata on the other 10 aggregates.
- **BREAKING** (write-side): every aggregate's `type Metadata` changes from `()` (or `MembershipMetadata`) to the shared `EventMetadata`. Each command adapter injects `actor` and `series_id` (denormalized, Option A) at dispatch time. `series_id` is resolved in the adapter so the audit projector never chains entity→series at read time.
- Generalize `AuditProjector` from `BlockMembership`-only to an exhaustive `EntityEventHandler` per aggregate category (season, block, episode, scene, scene_shoot, shooting_day, character, costume, costume_category, photo, membership), all writing into the existing `projection_audit` table with the same idempotent `event_key` strategy.
- Generalize `EventMetadata.actor`/`provenance` capture and `series_id` population in the projector, so every audit row carries tenant + actor + provenance uniformly. Legacies of pre-existing `()` aggregates carry `provenance = System`, `actor = NULL`, `series_id = NULL` (pre-prod, no backfill — see Non-Goals).
- Enforce at compile time that no aggregate category is missing its `AuditProjector` registration (exhaustive enum in the supervisor registration path, Option 5a).
- Surface the existing `AuditRepository` queries through any additional filtering needed (by `series_id`, by `provenance`) — no new port surface beyond minor additions to the existing one.

### Non-Goals
- Backfill of `actor`/`provenance`/`series_id` for pre-existing historical events of the 10 previously `()`-aggregates. The backend is not yet in production; pre-change history is honestly `NULL`/`System`. No migration chapter is scoped.
- Serving the audit history directly from the SierraDB event store. SierraDB offers only `ESCAN`/`EPSCAN`/`EGET` (sequential partition/stream reads, no server-side cross-stream attribute index, no reverse-filtered pagination), so direct-from-store querying is architecturally and practically non-viable for an admin UI. The event store remains the authoritative source-of-truth for *replay*; the projection remains the access path for the *history view*.

## Capabilities

### New Capabilities
- `audit-history`: Cross-cutting, projection-backed audit history over all aggregate categories — covers `EventMetadata` design, generalized `AuditProjector` coverage, `series_id` tenant scoping via denormalization, `provenance` discriminator, and the compile-time guard against missing audit handlers.

### Modified Capabilities
- `persistence-projections`: Adds a generalized audit projector covering all 11 entity categories (currently only `membership`); adds compile-time exhaustiveness enforcement of audit-projector registration per aggregate category alongside the existing per-projector event-variant exhaustiveness.

## Impact

- **`crates/core`**: new `shared::EventMetadata`, `Provenance` enum; `MembershipMetadata` aliased/superseded; all 11 aggregates' `type Metadata` updated; `AuditEntry` view gains `series_id` populated for all categories (already has the field, currently `NULL`).
- **`crates/infra`**: `AuditProjector` generalized (one `EntityEventHandler` impl per category, or an exhaustive dispatcher); command adapters inject `actor` + `series_id` metadata at dispatch; supervisor registration gains a compile-time exhaustive enum so adding an aggregate without registering its audit projector fails to build; `AuditRepositoryImpl` query surface gains `list_by_series` / `list_by_provenance` (or equivalent) filters as needed.
- **`crates/api`**: no new public endpoint change required beyond surfacing existing audit queries by `series_id` for the admin history view.
- **Migrations**: `projection_audit` schema is already generic (`series_id` column exists). No DDL changes required for the core audit row.
- **Tests**: new architecture/unit test asserting all aggregate categories have a registered audit projector (exhaustive enum); existing audit projector tests extended to cover non-membership categories.
