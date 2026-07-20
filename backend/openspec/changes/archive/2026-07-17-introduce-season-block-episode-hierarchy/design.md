## Context

Today `crates/core` has four Bounded Contexts — `scene`, `character`, `costume`, `calculation` — all threaded onto a single opaque `ProjectId` (`crates/core/src/shared.rs`). There is no `Project` aggregate; `ProjectId` is passed by hand into every `Create*` command. Stakeholder input refined the actual production structure into a four-level hierarchy (Series → Season → Block → Episode) and revealed that `ProjectId` was silently playing four *different* scope roles that must now be disentangled:

| Today's `project_id` on… | Actually means… | Becomes |
|---|---|---|
| `Scene` | the work-unit (an Episode) | `episode_id` |
| `Character` | the production (a Season) | `season_id` |
| `Costume` | nothing the stakeholder needs | removed (scope-free) |
| `Calculation` | a requirement nobody has | removed (context deleted) |

Separately, the in-flight change `add-oidc-auth-and-membership` plans to scope membership per `ProjectId`. Stakeholder clarified that costume-department staff *rotate roles at Block boundaries* — so membership's natural authorization scope is the **Block**, not the Season and not the Episode. That reformulation is handled in the auth change's own specs; this change establishes the `Block` aggregate on which it can land.

We are **pre-production**: dev compose only, no real events in SierraDB. This is the cheapest moment for a schema-breaking refactor of the event-sourced domain.

Constraints (from AGENTS.md + existing ADRs):
- UUIDv7 only (`Uuid::now_v7()`).
- Hexagonal architecture: ports in `core`, adapters in `infra`.
- CQRS + Event Sourcing via `kameo_es`; aggregates are `kameo::Actor`s implementing `kameo_es::Entity`.
- No `cargo-mutants`/`rust_arkitect`/`cargo-deny` regressions allowed.

## Goals / Non-Goals

**Goals:**
- Introduce `SeriesId` (opaque) plus `Season` / `Block` / `Episode` aggregates, each following the established `aggregate/commands/events/error/ports/views` module shape.
- Repurpose each existing context onto its *correct* scope (`scene` → episode, `character` → season, `costume` → scope-free).
- Replace the ambiguous `is_main_character`/`is_extra` bool pair with a single exhaustive `CharacterCategory` enum.
- Remove `calculation` entirely (it encoded a requirement the stakeholder does not have).
- Keep `core` pure (no `sqlx`/`axum`) — boundary enforced by architecture tests.
- Leave a clean seam (opaque `SeriesId`, additive `category` enum, additive future `Actor`/`Series` aggregates) so multi-show support and actor-master records can arrive as **non-breaking** future changes.

**Non-Goals:**
- The `Series` aggregate (name, year, status). `SeriesId` stays opaque, exactly as `ProjectId` does today. Adding it later is additive.
- The `Actor` aggregate (cross-season measurements/contact). Measurements/contact stay on the (season-scoped) `Character` for v1; an optional `actor_id` can be added later without a schema break.
- Membership & authorization. Belongs to `add-oidc-auth-and-membership` (reformulated in that change). This change only provides the `Block` aggregate that membership will hang off.
- Block time-span *enforcement*. `start_date`/`end_date` are `Option<NaiveDate>`; the model accepts "not filled in" even though reality always has a span.
- Restructuring the Block↔Episode or Season↔Block containment as a stored vector on the parent aggregate. Containment lives in the **read model** (projection), derived from events — see Decision 4.

## Decisions

### 1. Four-level hierarchy; `Series` is an opaque ID, not an aggregate
**Decision.** `SeriesId(Uuid)` is a value type in `shared.rs` mirroring `ProjectId`. `Season`, `Block`, `Episode` are full aggregates. `Series` (with metadata) is *not* modeled — it is a future, additive change.
**Rationale.** Stakeholder confirmed multi-show usage is "currently not, but conceivable in future." An opaque ID preserves the multi-show seam (every aggregate already carries `series_id` and a unique index on `(series_id, number)`) without paying for a `Series` aggregate that has no requirements yet. A future `Series` aggregate can subscribe to existing events and add new ones (RenameSeries, ArchiveSeries) without touching any existing event schema.
**Alternatives.** (a) `Series` as a full aggregate now — rejected; the only invariant it could own (series-global numbering) is enforced more cheaply by a Postgres unique index, and a stream-locked `Series` aggregate would serialize every Episode/Season creation across the whole show. (b) No `SeriesId` at all (one show per deployment) — rejected; "conceivable in future" is exactly the seam opaque IDs are for, and retrofitting `series_id` later would be a second schema break on already-evented data.

### 2. Numbers are series-global running counters, enforced in the read model
**Decision.** `Season.number`, `Block.number`, and `Episode.number` are each unique within a `Series`, *not* within their parent. Uniqueness is enforced by a Postgres unique index on `(series_id, number)` in the projection, not by the write-side aggregate.
**Rationale.** Stakeholder: episode numbers count up from the start of the show (not reset per Season/Block); same for Season and Block numbers. Because the invariant spans the whole series, no single child aggregate can preventively guarantee it without reading siblings — which the write side is forbidden from doing (CQRS read/write split). A unique index makes collisions surface deterministically at projection time and is the standard CQRS handling for cross-aggregate uniqueness.
**Alternatives.** (a) `CreateEpisode` as a command on the `Series` aggregate, with the series carrying its numbering counter — rejected: the `Series` aggregate would become a contention bottleneck for every episode across every block. (b) Preventive counter service — rejected: over-engineering a problem a unique index already solves.
**Trade-off accepted.** A numbering collision is detected *after* the aggregate accepted the command (at projection time). Mitigations: the API layer reads the projection (best-effort) before dispatch and returns 409; the projector emits a compensating signal. Collisions are rare (manual, low-volume numbering in a costume department) and the cost of full prevention is disproportionate.

### 3. Aggregate shapes — narrow state, parent referenced by ID
**Decision.** Each new aggregate holds only its own fields plus a parent reference; no aggregate stores a vector of child IDs.
```
Season  { id, series_id, number: i32, title: Option<String> }
Block   { id, season_id, number: i32,
          start_date: Option<NaiveDate>, end_date: Option<NaiveDate> }
Episode { id, block_id: BlockId, series_id: SeriesId, number: i32,
          name: Option<String> }
```
**Rationale.** Independent streams per aggregate → no lock contention between Episode-Rename in Block 1 and Episode-Create in Block 2 (the failure mode that killed the "store children vector on parent" shortcut). Containment (Season→Blocks→Episodes tree) is a *read-model* concern derived from events, where it belongs.
**`series_id` denormalized on `Episode`.** Although `series_id` is derivable via `Episode.block_id → Block.season_id → Season.series_id`, Episode queries and the numbering unique index need it directly. Storing it denormalized on the event/aggregate avoids a 3-level join on the hot path and pays nothing in correctness (a Block can never change Season).
**Alternatives.** (a) `Block` carries `episodes: Vec<Uuid>` as the stakeholder originally described — rejected; this re-concentrates mutation on the parent stream and duplicates the Scene→Character assignment truth. (b) Derive `series_id` only via joins — rejected; cheapest-that-is-correct is to denormalize an immutable fact.

### 4. Containment is read-model-derived, never an aggregate vector
**Decision.** "Season X has which Blocks? Block Y has which Episodes?" are answered by **projection queries** (`SELECT … FROM blocks WHERE season_id = X ORDER BY number`), not by any stored `Vec` on `Season`/`Block`. Same pattern for "which Episodes does Character C appear in?" — derived from `scene_characters` projection (the existing Scene↔Character assignment relation).
**Rationale.** There are two sources of truth for "Character appears in Episode E": the Character's own `appearances` vector (if we stored one) and `Scene.episode_id` joined with `scene_characters.character_id`. Storing both creates a synchronisation burden and a mutants-testing surface. Deriving appearances from the assignment relation makes "assign Character to Scene" the single, natural input action — which is exactly the costume department's real workflow — and returns Main-Cast/Guest/Extra for free under one mechanism.
**Alternatives.** (a) `appearances: Vec<EpisodeId>` on the Character aggregate, maintained by a command — rejected; redundant with Scene assignments, and Main-Cast-not-in-every-Episode means you'd still enumerate them. (b) A separate `Appearance` aggregate — rejected; over-modelling one relation.

### 5. `CharacterCategory` replaces the bool pair
**Decision.** Replace `is_main_character: bool` + `is_extra: bool` with a single `enum CharacterCategory { MainCast, Guest, Extra }`. The enum is designed for purely additive extension (new variants are backwards-compatible deserialization). Seasons scope Characters: a Character references `season_id` (not `project_id`).
**Rationale.** The bool pair is non-exhaustive (can't add "Recurring Guest" without another bool) and admits illegal states (`is_main_character=true, is_extra=true`). A single enum is exhaustive, matches authorization matching, and the stakeholder's own language ("Main-Cast", "Episodenrollen", "Komparsen") maps directly to variants. Season-scoping reflects that Main-Cast Characters persist across the whole season (and their costumes, measurements, and contact info with them), which is the entire reason Costumes do *not* need a per-episode scope.
**Alternatives.** (a) Keep bools, add a third — rejected; bools compose badly and lose exhaustiveness. (b) Free-form `String` category — rejected; loses compile-time matching in the authorization layer.

### 6. Costume is scope-free; bound only to `character_id`
**Decision.** `Costume` loses `project_id`. A Costume carries `character_id: Option<Uuid>` and nothing else that ties it to a production level. The existing assign/unassign commands (`CostumeAssignedToCharacter`, `CostumeUnassigned`) are unchanged in shape.
**Rationale.** Stakeholder: constantly re-creating costumes per Episode/Block would be wasted data entry. A Costume belongs to the Character it dresses (Main-Cast costumes live for the season, Guest/Extra costumes for the episode the Character exists in — but that fact is already encoded by the Character's season/episode scope, not the Costume's). Removing the link keeps the Costume model honest about what the stakeholder actually needs.
**Alternatives.** (a) Keep `project_id` for filtering — rejected; filtering is done via `Costume.character_id → Character.season_id` in the read model, no information lost. (b) Scope Costumes to Episode — explicitly rejected by stakeholder.

### 7. Remove `calculation` entirely
**Decision.** Delete the `calculation` Bounded Context in full: `crates/core/src/calculation/`, its infra (projector/query/command-adapter/migration), its API handlers/routes, and its tests.
**Rationale.** Stakeholder confirmed they don't want to calculate in v1. The existing implementation encodes a guessed-at, never-confirmed requirement; refactoring it onto a hierarchy it never belonged to would be polishing dead code. Removing now (pre-production, event-store empty) is mechanical and free; removing later (with historical events) would be impossible. If the requirement returns, the version built then reflects real scope/feld needs — not a retrofit.
**Alternatives.** (a) Keep it but unused — rejected; dead code accrues boundary-test, mutation-test, and review cost and would have to be renamed through the hierarchy refactor for nothing. (b) Feature-flag it off — rejected; same carrying cost plus a flag to maintain.

## Risks / Trade-offs

- [Event-schema break on existing four contexts] → Mitigation: pre-production, no real events in SierraDB; the break is exactly the refactor. All projectors/migrations/integration-tests updated in the same change; `openspec validate` + `cargo test` + `cargo mutants` + `cargo deny check bans` + `cargo test -p architecture_tests` gate the merge.
- [Cross-aggregate numbering uniqueness is eventual, not preventive] → Mitigation: API-layer pre-check against projection (409 on likely collision); rare in practice (manual numbering, low volume); projector surfaces compensating signal. Accepted trade-off vs. the contention cost of preventive enforcement.
- [`series_id` denormalized on `Episode` creates a second place to keep it] → Mitigation: `series_id` is immutable for a given Episode (a Block never changes Season), so there is no second-place-to-update; it is write-once. No consistency risk.
- [Membership change (`add-oidc-auth-and-membership`) depends on `Block` existing] → Mitigation: this change lands *first*; the auth change is reformulated to `BlockId`-scoped membership as its own spec revision before implementation. Sequencing is documented in both changes' proposals.
- [Removing `calculation` loses written code] → Mitigation: Sunk cost; the git history preserves it if real requirements ever emerge. Acceptable per stakeholder input.
- [No `Actor`/`Series` aggregates now limits cross-season features] → Mitigation: both are additive future changes (optional `actor_id` on Character; new `Series` aggregate subscribing to existing events). The seams are deliberately left open.

## Migration Plan

Pre-production, so there is no live-data migration:
1. Land `production-hierarchy` (SeriesId + Season/Block/Episode aggregates + projectors + migrations + queries + handlers + tests) as the foundation. Other changes can compile against it.
2. Repoint `scene` to `episode_id`, `character` to `season_id` + `category`, `costume` to scope-free — each in its own commit, with matched projector/migration/query/handler/test updates.
3. Delete `calculation` (core, infra, api, tests) in one mechanical commit.
4. Run the full guardrail gate: `cargo test`, `cargo mutants`, `cargo deny check bans`, `cargo test -p architecture_tests`, `cargo test -p integration-tests` (Tier 1–4).
5. Update `AGENTS.md` workspace-structure section to list the new/removed contexts.
6. Hand off to `add-oidc-auth-and-membership` reformulation (BlockId-scoped membership).

## Open Questions

- Should `Block` carry a human label (e.g. "Drehblock Hamburg") beyond `number`? Stakeholder's original description only listed `number`, so v1 ships `number` only; a `title: Option<String>` can be added additively. To confirm with stakeholder at implementation time, not blocking.
- Whether the API-layer pre-check for numbering collisions should return 409 or 422 — a small API-design detail to settle during implementation, not a spec question.
