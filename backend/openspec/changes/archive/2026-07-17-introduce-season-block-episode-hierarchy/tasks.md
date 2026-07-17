## 1. Foundation: SeriesId + Season/Block/Episode aggregates

- [x] 1.1 Add `SeriesId` opaque value type to `crates/core/src/shared.rs` (mirror `ProjectId`/`AggregateVersion` — UUIDv7, serde transparent, ToSchema, tests)
- [x] 1.2 Create `crates/core/src/season/` module (aggregate/commands/events/error/ports/views/mod); `Season` state `{ id, series_id, number, title }`; `SeasonCreated`, `SeasonRenamed` (optional); `category = "season"`
- [x] 1.3 Create `crates/core/src/block/` module; `Block` state `{ id, season_id, number, start_date, end_date }`; `BlockCreated`, `BlockTimeSpanUpdated`; `category = "block"`
- [x] 1.4 Create `crates/core/src/episode/` module; `Episode` state `{ id, block_id, series_id, number, name }`; `EpisodeCreated`, `EpisodeRenamed`; `category = "episode"`
- [x] 1.5 Write unit tests in `core` for each new aggregate (create happy-path, mutation apply, version-bump); ensure every command has a mutation test suitable for `cargo mutants`

## 2. Infra: projectors, queries, command adapters for the new contexts

- [x] 2.1 Create `crates/infra/migrations/` for `seasons`, `blocks`, `episodes` tables (id, series_id, number, title/dates/name, version) with unique indexes on `(series_id, number)`
- [x] 2.2 Implement `season`, `block`, `episode` projectors in `crates/infra/src/projectors/` (idempotent upsert pattern mirroring existing projectors); register in `PostgresProcessor` set
- [x] 2.3 Implement `season`, `block`, `episode` query repositories in `crates/infra/src/queries/` (by series_id, by parent, by number)
- [x] 2.4 Add command adapters in `crates/infra/src/event_store/command_adapters.rs` for the new contexts (version translation per AGENTS.md `domain_version = stream_version + 1`)
- [x] 2.5 Update `main.rs` composition root to spawn the three new projectors and register the new query repositories

## 3. API: handlers + OpenAPI for the new contexts

- [x] 3.1 Add `Season`/`Block`/`Episode` handlers in `crates/api/src/handlers/` (create, rename/update, list-by-parent)
- [x] 3.2 Add OpenAPI types and routes; expose on `/swagger-ui`
- [x] 3.3 API-layer pre-check for duplicate `(series_id, number)` against the projection, returning 409 on likely collision (best-effort, eventual-consistency aware)

## 4. Repoint Scene to Episode

- [x] 4.1 In `crates/core/src/scene/`: replace `project_id: ProjectId` with `episode_id: EpisodeId` in events, commands, aggregate state, ports, views
- [x] 4.2 In `crates/infra/src/projectors/scene.rs` + migration: project `episode_id`, drop `project_id`; update queries by `episode_id`
- [x] 4.3 Update `crates/api` Scene handlers/OpenAPI types to `episode_id`
- [x] 4.4 Update integration-test fixtures asserting on `project_id` for Scene

## 5. Repoint Character to Season + introduce category

- [x] 5.1 Add `CharacterCategory` enum (`MainCast | Guest | Extra`) to `crates/core/src/character/` (serde, additive-design note)
- [x] 5.2 Replace `is_main_character: bool` + `is_extra: bool` with `category: CharacterCategory`; replace `project_id` with `season_id` in events, commands, aggregate state, ports, views
- [x] 5.3 In `crates/infra`: character projector/migration stores `season_id` + `category`, drops `project_id` and the two bools; queries by `season_id`/`category`
- [x] 5.4 Add derived `appearances` read-model query (join `scene_characters` × `scenes.episode_id`) and remove any `Vec<EpisodeId>` from the aggregate
- [x] 5.5 Update `crates/api` Character handlers/OpenAPI types
- [x] 5.6 Update integration-test fixtures for Character

## 6. Make Costume scope-free

- [x] 6.1 In `crates/core/src/costume/`: remove `project_id` from events, commands, aggregate state, ports, views (keep `character_id: Option<Uuid>`)
- [x] 6.2 In `crates/infra`: costume projector/migration drops `project_id`; add Costume-by-Season query joining `character_id → characters.season_id`
- [x] 6.3 Update `crates/api` Costume handlers/OpenAPI types
- [x] 6.4 Update integration-test fixtures for Costume

## 7. Remove calculation context

- [x] 7.1 Delete `crates/core/src/calculation/` and remove from `lib.rs`
- [x] 7.2 Delete `crates/infra/src/projectors/calculation.rs`, `queries/calculation.rs`, related command adapter, and calculation migrations
- [x] 7.3 Delete calculation handlers/routes/OpenAPI in `crates/api`
- [x] 7.4 Delete calculation integration tests
- [x] 7.5 Remove calculation registrations from `main.rs` and the `PostgresProcessor` spawn set

## 8. Guardrails & docs

- [x] 8.1 Run `cargo test` (all workspace) green
- [x] 8.2 Run `cargo mutants` green (whitebox `#[cfg(test)]` modules); add/improve mutants tests for new aggregates and the category/exhaustiveness invariant
- [x] 8.3 Run `cargo deny check bans` green
- [x] 8.4 Run `cargo test -p architecture_tests` green; update `rust_arkitect` assertions if new core modules are listed
- [x] 8.5 Run `cargo test -p integration-tests` (Tier 1–4) green; add Season/Block/Episode projector + round-trip tests
- [x] 8.6 Update `AGENTS.md` workspace-structure section (add `season`/`block`/`episode` contexts, remove `calculation`, note `SeriesId` opaque seam)
- [x] 8.7 Add SPDX headers to new files via `./scripts/add-spdx-headers.sh`
- [x] 8.8 Confirm `add-oidc-auth-and-membership` change owner reformulates membership specs to `BlockId`-scoped before that change is implemented (cross-change handoff note)

## Cross-change handoff

- **`add-oidc-auth-and-membership` owner:** This change introduces `BlockId` and the
  `Series → Season → Block → Episode` hierarchy. Membership / authorization specs in that
  change MUST be reformulated to be `BlockId`-scoped (not `ProjectId`-scoped) before it is
  implemented, since `ProjectId` scoping has been removed here. The `SeriesId` opaque type is
  a deliberate seam for a future `Series` aggregate — prefer referencing `SeriesId` over
  introducing a concrete `Series` entity.
