## Context

`breakdown-rs` is an event-sourced CQRS app (ADR-002). Today an audit projection exists but is scoped to the single `membership` aggregate ("v1"). The `AuditRepository` port, `projection_audit` table, `AuditProjector`, and `AuditRepositoryImpl` are all already generic in shape (`list_by_entity(entity_type, entity_id, …)`, `series_id` column present but `NULL`) — only the projector's `EntityEventHandler<BlockMembership, …>` impl is single-category.

Meanwhile, only `BlockMembership` carries the authenticated actor in its command `Metadata`; the other 10 aggregates (`season`, `block`, `episode`, `scene`, `scene_shoot`, `shooting_day`, `character`, `costume`, `costume_category`, `photo`) declare `type Metadata = ()`, so they record *no* actor provenance. The membership metadata is also semantically overloaded: `actor: Option<UserId>` conflates "no actor supplied" with "dispatched by a saga" — both surface as `None`.

The audit history view needs: paginated filters by actor, by entity, by time range, and by tenant (`series_id`); reverse-chronological ordering; block-scoped authorization; and display enrichment (entity display names). The backend is not yet in production, so no historical backfill is required.

## Goals / Non-Goals

**Goals:**
- Provide a cross-cutting audit history over *all* 11 aggregate categories, backed by the generalized `projection_audit` projection.
- Capture *who* triggered every event via a shared `EventMetadata`, with a `provenance` discriminator that distinguishes `Human`, `Saga`, and `System` actors honestly.
- Populate `series_id` on every audit row at projection time without runtime entity→series chain resolution, so the projector has zero ordering dependency on parent aggregate projectors.
- Make the audit-projector coverage matrix compile-time-exhaustive: adding an aggregate without registering its audit projector fails to build.
- Preserve ADR-002's read/write separation: audit history is read from the Postgres projection, never by querying SierraDB directly.

**Non-Goals:**
- Serving the history view directly from the SierraDB event store (Non-viable — see Decision 1).
- Backfilling `actor`/`provenance`/`series_id` for pre-existing historical events of the previously `()`-aggregates. The backend is pre-production; pre-change history is honestly `NULL`/`System`.
- Changing the existing `projection_audit` DDL (`series_id` column is already present) or the idempotent `event_key ON CONFLICT DO NOTHING` strategy.

## Decisions

### Decision 1 — Audit history is read from the Postgres projection, NOT directly from SierraDB

**Choice:** Generalize `projection_audit` as the access path; SierraDB remains the source-of-truth for replay only.

**Rationale:** SierraDB's documented API surface is `ESCAN <stream_id> <start> <end>`, `EPSCAN <partition_id> <start> <end>`, and `EGET <event_id>` — sequential stream/partition reads with no server-side cross-stream attribute index, no actor/entity-type filter, and no reverse-paginated `LIMIT/OFFSET`. Events are distributed across 32 partitions via consistent hashing, so cross-stream reads require scanning multiple partition logs in application code. None of the UI's query needs (filter by actor, by `entity_type`, by `series_id`; reverse-chronological; paginated; authorization-scoped; display-enriched via joins) are expressible against this API at any reasonable cost.

A projection is not a *second* source of truth — it is an indexed access path *over* the EventStore, deterministically derived and idempotently rebuilt from `$all`-style replays. Keeping the read in the projection upholds ADR-002 ("Queries read from flat PostgreSQL Projections. Never query aggregates directly for views") and lets us reuse the existing generic `AuditRepository` port unchanged.

**Alternatives considered:**
- *Direct SierraDB read for the UI.* Rejected for the API limitations above.
- *Hybrid (UI → projection; raw export → SierraDB).* Accepted as the long-term shape: an append-only JSONL / compliance dump may stream from SierraDB partitions in the future, but the *history view* is projection-backed. This keeps each store's strength (sequential replay for SierraDB; indexed reads for Postgres) without conflating them.

### Decision 2 — Shared `core::shared::EventMetadata` replaces `MembershipMetadata` and the 10 `()` metadata types

**Choice:** Every aggregate's `Entity::Metadata` becomes `core::shared::EventMetadata`.

```
pub struct EventMetadata {
    pub actor:     Option<UserId>,        // OIDC `sub`, None for Saga/System
    pub provenance: Provenance,
    pub series_id: Option<SeriesId>,       // denormalized tenant key (Decision 3)
}

pub enum Provenance { Human, Saga(&'static str), System }
```

**Rationale:** A single type lets the audit projector extract `actor`/`provenance`/`series_id` uniformly, without per-aggregate branching — the projector becomes a genuinely generic handler. The `provenance` discriminator removes the semantic overloading of `actor = None` (previously that conflated "missing", "saga-dispatched", and "system"). Sagas (e.g. `SeasonSeedingSaga` → `CreateCostumeCategory`, photo sagas → `DeletePhoto`) declare themselves via `Provenance::Saga("SeasonSeeding")` etc., so the audit row honestly shows who/what acted.

**Alternatives considered:**
- *Per-aggregate metadata structs.* Rejected — duplicates the actor field across 11 types; the projector must branch on type to extract the actor; no path to a single generic projector.
- *Keep `MembershipMetadata`, add `actor` to each `()` aggregate via a new local struct.* Rejected for the same reason; uniformity is the whole point.

### Decision 3 — `series_id` is denormalized in command metadata (Option A), not resolved at projection time

**Choice:** Each command adapter resolves `series_id` at dispatch time (a single read on the write path, via the relevant repository) and injects it into `EventMetadata.series_id`. The audit projector copies `series_id` from metadata verbatim — zero entity→series chain resolution at read time.

**Rationale:** The ordering problem is decisive. If the audit projector resolved `series_id` from a helper table (or by walking scene→episode→block→series) at projection time, it would depend on parent aggregate projectors having already run. But each event is processed in its *own* worker transaction, and `BlockCreated` / `SeasonCreated` for the parent arrives on a *different* SierraDB stream with no ordering guarantee relative to a child's event. That is exactly the FK-violation gotcha documented in `AGENTS.md`. Denormalizing `series_id` in metadata at the point of command dispatch — where the command struct already carries `season_id` / `block_id` / `series_id` (e.g. `CreateBlock`, `CreateEpisode` carry `series_id` directly; `Scene`/`Character`/`Costume` carry `season_id` from which one lookup resolves the parent `series_id`) — eliminates the ordering dependency entirely. "Series is constant" supports this: once set, the value is correct forever, so a single write-path read is sufficient.

This also matches the existing pattern: `Block` and `Episode` already denormalize `series_id` into their *event payloads* for the same reason (`projection_block` series-global numbering). We are extending the same principle to metadata.

**Alternatives considered:**
- *Option B — Lazy payload extraction with `NULL` fallback.* Rejected as the target shape: works incrementally but leaves tenant-scoping incomplete for the 7 aggregates that don't carry `series_id` in their payload. Acceptable only as a transitional implementation step; we go straight to A since the backend is pre-prod (no migration budget pressure).
- *Option C — `projection_entity_series(entity_id, series_id)` helper table joined at read time.* Rejected: reintroduces the ordering dependency (helper row may not exist yet), adds a table, and adds JOIN cost. A's denormalization is strictly better.

### Decision 4 — `AuditProjector` is generalized per-category; supervisor registration is compile-time-exhaustive (Option 5a)

**Choice:** Introduce an exhaustive `AuditCategory` enum whose variants are the 11 aggregate categories. Supervisor registration matches on this enum exhaustively; a new aggregate type MUST add a variant (else compile error) and MUST register an audit projector for it (else the match is non-exhaustive).

```
#[non_exhaustive]
pub enum AuditCategory {
    Season, Block, Episode, Scene, SceneShoot, ShootingDay,
    Character, Costume, CostumeCategory, Photo, Membership,
}
```

**Rationale:** "Forgotten audit projector for a new aggregate" is exactly the kind of oversight that compiles silently today (each `EntityEventHandler` impl is independent). A compile-time enum makes the coverage matrix a compile-time invariant — the cheapest, fastest-failing guard possible. `#[non_exhaustive]` keeps the door open for out-of-crate growth without forcing downstream breakage.

This is supplemented by a small, well-named unit test that documents *why* the enum exists (the "this is the forgotten-projector guard" test) so future readers understand its purpose. The enum itself is the source of truth; the test is documentation, not a second truth.

**Alternatives considered:**
- *Runtime unit test with a separate `KNOWN_CATEGORIES` const.* Rejected as primary — the const list is itself a "forgottable thing"; if someone adds an aggregate but forgets both the variant and the const, the test passes. The compile-time enum avoids this.
- *`rust_arkitect` source-level architecture test.* Rejected for this purpose — `rust_arkitect` is excellent at boundary rules ("core must not depend on infra") but ill-suited to asserting runtime registration. It stays in its existing role.

## Risks / Trade-offs

- **[Write-path read for `series_id` resolution]** → Each command adapter gains one read on the write path to resolve `series_id`. For aggregates whose command payload already carries it (`CreateBlock`, `CreateEpisode`), zero additional reads. For others, one repository lookup. Mitigation: the lookup is against an already-existing projection row, which is cheap; and `series_id` is stable so no consistency concern.
- **[`actor = None` for pre-existing history of the 10 ex-`()` aggregates]** → Pre-change events honestly have no actor. Mitigation: explicitly accepted (Non-Goal); the history view will show these rows as `provenance = System, actor = NULL` rather than fabricating data.
- **[Saga dispatches must declare `Provenance::Saga(name)`]** → Each saga that dispatches commands must be updated to inject its name, or it will default to `System`/`None`. Mitigation: the compile-time-exhaustive enum (Decision 4) does not catch this; instead the spec's scenarios call out "saga-dispatched command records `provenance = Saga(name)`". Reviewers must check saga adapters explicitly.
- **[Audit projector is now one more handler per category to register]** → Slight supervisor-boilerplate increase. Mitigation: the exhaustive enum guarantees it is never silently missing.
- **[Audit projection lag vs. event store]** → Eventual consistency (~ms–~1s) between event append and projected audit row. Mitigation: bounded-retry polling already used elsewhere (Tier-4 tests) applies; the audit view tolerates brief lag because it is an administrative read, not in the request-write path.

## Migration Plan

Pre-production, so no data migration is required. Rollout is a single coordinated change:

1. Introduce `EventMetadata` + `Provenance` in `crates/core/src/shared.rs`.
2. Switch all 11 aggregates' `type Metadata` to `EventMetadata` (compile-time exhaustive check forces all to be touched).
3. Update each command adapter in `crates/infra/src/event_store/command_adapters.rs` to inject `actor` (from the authenticated `UserId`) and `series_id` (denormalized). Sagas inject `Provenance::Saga(<name>)`; system-initiated commands inject `Provenance::System`.
4. Generalize `AuditProjector` — one `EntityEventHandler` per category writing to `projection_audit` with the same `event_key ON CONFLICT DO NOTHING` idempotency pattern.
5. Add the `AuditCategory` enum and exhaustive supervisor-registration match.
6. Add the documentation-style unit test asserting the enum exists and is matched exhaustively.
7. Rollback: revert the change; `projection_audit` DDL is unchanged, so pre-existing membership audit rows remain valid. The generalized projector can be safely dropped without data loss to the membership-only baseline.

## Open Questions

- Should the eventual compliance/JSONL export (raw dump from SierraDB) be in scope for a *later* change, or do we keep the audit history purely projection-backed indefinitely? Current design leaves it open (Non-Goal here).
- For `Photo`-saga-dispatched commands (`DeletePhoto` etc.), what naming convention do we adopt for `Provenance::Saga(&'static str)` strings — module path, saga name, or a stable symbolic id? Suggested: stable symbolic id matching the saga's type name (e.g. `"PhotoDeletionSaga"`), to keep audit rows stable across refactors.
