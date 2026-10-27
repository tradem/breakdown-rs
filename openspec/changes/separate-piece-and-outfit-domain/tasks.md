<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go)

# Tasks — Separate `Piece` and `Outfit`

Clean cut, no legacy shims: `Costume` becomes `Piece` (fundus, no
`character_id`) and `Outfit` (character look) is introduced. Ordering is
`core → infra → api`; the workspace must compile after each phase.

## 1. Core — Piece aggregate

- [x] 1.1 Add `crates/core/src/piece/` (mod, aggregate, commands, events, error, ports, views) as the clean-cut successor of `crates/core/src/costume/`: state `{ id, name, category_id, seasons, notes, details, photos, version }`, stream category `"piece"`, **no** `character_id`.
- [x] 1.2 `PieceCreated { id, name, category_id, season_id, notes, details, photos, version }` + `PieceRenamed`, `PieceNotesUpdated`, `PieceCategorySet`, `PieceAddedToSeason`, `PieceRemovedFromSeason`, `PieceDetailAdded/Updated/Removed`, `PiecePhotoLinked/Unlinked`.
- [x] 1.3 Enforce a non-blank `name` on `CreatePiece`/`RenamePiece` (`PieceError::EmptyName`), trim surrounding whitespace, no uniqueness constraint.
- [x] 1.4 Keep the repertoire semantics idempotent (repeat add / absent remove ⇒ no event, unchanged version).
- [x] 1.5 Drop the legacy first-wins `derive_category_id` replay rule and `CostumeDetail.category_id` (clean cut).
- [x] 1.6 Define `PieceCommands` / `PieceRepository` ports (`find_by_id`, `list_by_season`, `repertoire_seasons`) and `PieceView`/`PieceDetailView`/`PiecePhotoView` read models with `season_ids`.
- [x] 1.7 Unit tests in `piece/`: blank name, category set/clear/no-op, repertoire idempotency, detail CRUD, photo link idempotency, version monotonicity.

## 2. Core — Outfit aggregate

- [x] 2.1 Add `crates/core/src/outfit/` (mod, aggregate, commands, events, error, ports, views), stream category `"outfit"`, state `{ id, character_id, name, piece_ids, variant_of, photos, notes, version }`.
- [x] 2.2 Commands/events: `CreateOutfit`/`OutfitCreated`, `CreateOutfitVariant`/`OutfitVariantCreated`, `RenameOutfit`/`OutfitRenamed`, `UpdateOutfitNotes`/`OutfitNotesUpdated`, `AddPieceToOutfit`/`OutfitPieceAdded`, `RemovePieceFromOutfit`/`OutfitPieceRemoved`, `LinkOutfitPhoto`/`OutfitPhotoLinked`, `UnlinkOutfitPhoto`/`OutfitPhotoUnlinked`.
- [x] 2.3 Invariants: non-blank `name`; `piece_ids` insertion-ordered and deduplicated with no category uniqueness; add-existing / remove-absent are no-event no-ops; `variant_of: Some(source)` set only by `CreateOutfitVariant` and never mutated afterwards.
- [x] 2.4 `CreateOutfitVariant` carries `source_outfit_id`, `character_id`, `name`, `piece_ids`, `notes` — resolved at the API edge; the aggregate and adapter never read the source stream or projection.
- [x] 2.5 Ports `OutfitCommands` / `OutfitRepository` (`find_by_id`, `list_by_character`) and `OutfitView { id, character_id, character_name, season_id, name, variant_of, piece_ids, notes, photos, version, updated_at }`.
- [x] 2.6 Unit tests in `outfit/`: empty shell, layering (two pieces of the same category), duplicate add no-op, variant fork unaffected by later edits, blank name rejection.

## 3. Core — scene beats, photo context, ids, registry

- [x] 3.1 Rename `SceneCostumeBeat` → `SceneOutfitBeat { character_id, outfit_id, order, note }` in `scene/costume.rs` (rename module to `outfit.rs`) and its re-exports.
- [x] 3.2 Rename the scene commands/events: `AddOutfitBeat`, `UpdateOutfitBeat`, `RemoveOutfitBeat`; `OutfitBeatAdded/Updated/Removed/BeatsCleared`; keep the dense `max+1` order rule, the consecutive-identical guard and the character-in-scene check.
- [x] 3.3 `SceneView.costume_beats` → `outfit_beats: Vec<SceneOutfitBeatView>` with `{ character_id, character_name, outfit_id, outfit_name, variant_of, order, note }`.
- [x] 3.4 Use plain `Uuid` ids for `piece_id` / `outfit_id` / `character_id`, consistent with the rest of the costume-side aggregates (no new id newtypes).
- [x] 3.5 Photo context: replace `PhotoBinding::Costume { costume_id }` with `PhotoBinding::Piece { piece_id }` and add `PhotoBinding::Outfit { outfit_id }`; update `Continuity.costume_id` → `piece_id` where it denotes a garment.
- [x] 3.6 Update `core/src/lib.rs` (drop `costume`, add `piece` + `outfit`) and every remaining `Costume*` re-export.
- [x] 3.7 Error registry: add `piece.not-found`, `piece.validation`, `piece-detail.not-found`, `piece.container-unresolved`, `outfit.not-found`, `outfit.validation`; remove the `costume.*` / `costume-detail.*` entries (never a standalone `const`, always via the `problem_codes!` macro).
- [x] 3.8 Scene aggregate unit tests updated: outfit beats, order denseness, clearing beats on `RemoveCharacter`.

## 4. Infra — schema and projections

- [x] 4.1 Migration (up + down) creating `projection_piece`, `projection_piece_season`, `projection_piece_detail`, `projection_piece_photo`, `projection_outfit`, `projection_outfit_piece` (with `position`, no FK to `projection_piece`), `projection_outfit_photo`, `projection_scene_outfit_assignment` (PK `(scene_id, character_id, "order")`, reverse index on `outfit_id`); drop the corresponding `projection_costume*` / `projection_scene_costume_assignment` tables.
- [x] 4.2 Piece projector (new `projectors/piece.rs`): version-guarded, idempotent, best-effort `category_name` resolution, `PhotoLinked/Unlinked` into `projection_piece_photo`.
- [x] 4.3 Outfit projector (new `projectors/outfit.rs`): version-guarded CRUD of outfit + piece rows (`position` preserved) + photo rows, tolerant of missing piece rows.
- [x] 4.4 Scene projector: rename beat handlers/tables to the outfit assignment table; keep delete-exactly-one-row semantics and no renumbering.
- [x] 4.5 Costume-category projector: rename propagation now targets `projection_piece.category_name`.
- [x] 4.6 Register the new projectors in `projectors/mod.rs` with the `"piece"` / `"outfit"` stream categories; remove the `"costume"` registration.

## 5. Infra — adapters, queries, sagas, AI apply

- [x] 5.1 Command adapters: `PieceCommandsImpl` and `OutfitCommandsImpl` in `event_store/command_adapters.rs`; delete `CostumeCommandsImpl`; no read-model access on the write side (`cqrs-boundary`).
- [x] 5.2 Query adapters: `PieceRepositoryImpl` (`queries/piece.rs`) and `OutfitRepositoryImpl` (`queries/outfit.rs`).
- [x] 5.3 `PieceView` enrichment: merge directly linked piece photos with photos linked to any outfit containing the piece, deduplicated by photo id.
- [x] 5.4 Scene queries: read `outfit_beats` fan-out-free (correlated-subquery pattern) with character name + outfit name/`variant_of`; tolerate a dangling `outfit_id`.
- [x] 5.5 `PhotoDeletionSaga`: refcount across `outfit`, `piece` and `scene_shoot` streams; a projection miss must not be treated as "zero references".
- [x] 5.6 Photo repository/bindings: piece and outfit photo tables, upload/list/delete paths for both bindings.
- [x] 5.7 AI apply/import paths compile against the new write model: `CreatePiece` + `UpdatePieceNotes` (+ `SetPieceCategory` left unset) and a per-figure `CreateOutfit`/`AddPieceToOutfit`; the successor change owns the refined AI semantics.
- [x] 5.8 Infra tests: projector idempotency (redelivery), piece/outfit queries, photo refcount saga, scene beat projection.

## 6. API — routes, handlers, authorization

- [x] 6.1 Replace the `/v1/costumes*` handlers with `/v1/pieces*` (create, get, list by season, name, notes, category, seasons, details, photo link/unlink); no alias routes remain.
- [x] 6.2 Add `/v1/outfits*` handlers (create, variant fork with the source resolved at the edge, get, list by character, name, notes, piece add/remove, photo link/unlink).
- [x] 6.3 Scene beat handlers/routes: `/v1/scenes/{id}/outfits*` with `outfit_id` in the body; remove `/v1/scenes/{id}/costumes*`.
- [x] 6.4 Authorization: rename/extend the costume-scoped policy helper to `authorize_piece_scoped` / add an outfit-scoped check that resolves the outfit's character season; every non-middleware-gated handler keeps an `// AUTHZ-GATE:` comment.
- [x] 6.5 API-edge pre-checks: `404 character.not-found` / `409 season.archived` on outfit create, `404 piece.not-found` on `AddPieceToOutfit`, intimacy of the `costume-category.*` pre-checks now keyed on the piece repertoire.
- [x] 6.6 Fluent `errors.ftl` (all locales): `problem-piece-*` / `problem-outfit-*` messages; retire the `problem-costume-*` keys.
- [x] 6.7 Handler tests: piece CRUD, outfit creation (incl. empty shell), variant fork, scene beat routes, 403 paths for each new AUTHZ-GATE, 404 on retired routes.

## 7. Contract, docs, verification

- [x] 7.1 Regenerate `backend/openapi.yaml` (`UPDATE_OPENAPI=1 cargo test -p api --test contract openapi_drift`) and review the diff: `/v1/pieces*`, `/v1/outfits*`, `/v1/scenes/{id}/outfits*`, `PieceView`, `OutfitView`, `SceneView.outfit_beats`.
- [x] 7.2 Regenerate the vendored Flutter client from the updated contract (`scripts/regen-client.sh`, byte-identical on re-run; the drift job passes).
- [x] 7.3 Update the docs that name the old model: `backend/AGENTS.md` §2 domain map, `.github/instructions/domain-model.instructions.md`, `docs/design/glossary.md` (Piece/Outfit terms).
- [x] 7.4 Audit `backend/rules/*.yml` + scripts for stale `costume` references that the rename breaks; update the `cqrs-boundary` / SQL rules only where paths moved.
- [x] 7.5 Full local gate: `cargo fmt --check`, `cargo clippy --workspace --all-targets -- -D warnings`, `cargo test -p core`, `cargo test -p infra`, `cargo test -p api`, `cargo test -p architecture_tests`, `cargo deny check bans`.
- [x] 7.6 Integration tests (`crates/integration-tests`): costumed fixtures rewritten to pieces/outfits (event + wire fixture snapshots regenerated, `MAJOR_BREAK_ALLOWLIST` entries added for the pre-1.0 clean cut); tier-4 adapter suite (`command_adapter_tests`) and the projector/query/photo suites drive `WardrobeCommandsImpl` (PieceCommands + OutfitCommands) with projector catch-up.
- [x] 7.7 Frontend port: the Flutter app follows the split end-to-end — drift cache v16 (`piece_cache_rows`/`fundus_piece_cache_rows` with the required `name`, new `outfit_cache_rows`, retired costume snapshots dropped), `PieceRepository` + `OutfitRepository`, wardrobe screens on pieces, scene beat picker on the character's outfits, photo bindings, `pubspec` `0.4.0-beta.14+106`, changelog, goldens. `flutter analyze` clean, `flutter test` 1853/1853.
- [ ] 7.8 Frontend UX follow-up (issue #739): dedicated outfit list/detail screens, piece↔outfit navigation, and the German wardrobe copy in the screens / `.pi/skills` copies / generated copy glossary — the remaining costume vocabulary on the presentation layer.
