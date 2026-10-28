<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

# Tasks — AI Import Pass 1: `DraftOutfit` and context-derived `DraftPiece`s

## 1. Core — draft extraction shape

- [x] 1.1 Add `DraftPiece { name, category_hint: Option<String>, description: Option<String> }` to `crates/core/src/ai/preview.rs`
- [x] 1.2 Add `DraftOutfitOrigin` (`ExplicitQuote` / `Derived`) with `#[serde(rename_all = "snake_case")]` and a grounded default
- [x] 1.3 Replace `DraftCostume` with `DraftOutfit { character_name, name, notes, source_quote, origin, pieces }`
- [x] 1.4 Replace `DraftScene.costumes` with `DraftScene.outfits` (serde-default, additive wire rule documented)
- [x] 1.5 Re-export the new types from `crates/core/src/ai/mod.rs` and drop the removed names

## 2. Core — outfit-level grounding

- [x] 2.1 Replace `verify_draft_costumes` with `verify_draft_outfits`: quote grounding on the outfit, character grounding against the scene's figures, pieces carried along
- [x] 2.2 Replace `RejectedCostume`/`RejectedCostumeReason` with `RejectedOutfit`/`RejectedOutfitReason` (stable slugs unchanged: `ungrounded_quote`, `unlisted_character`)
- [x] 2.3 Unit tests: grounded outfit keeps derived pieces, ungrounded outfit drops all its pieces, unlisted character rejected, folded-quote still grounds, empty piece list survives

## 3. Core — apply planner

- [x] 3.1 Add `PieceApplyPlan { ordinal, name, category_id, category_hint, notes }` and `OutfitApplyPlan { ordinal, character_identity, character_name, name, notes, source_quote, pieces }`
- [x] 3.2 Add the season category vocabulary input (`CategoryVocabularyEntry { name, id }`) resolved at the API edge; match `category_hint` case-insensitively, leave `category_id: None` on a miss
- [x] 3.3 Replace `CostumeDecision`/`ApplyMapping.costume_decisions` with `OutfitDecision`/`outfit_decisions` (absent ordinal ⇒ accepted; `costume_decisions` kept as a serde alias so a pre-rename client's rejection is never silently defaulted to accepted)
- [x] 3.4 Rework `plan_scene_apply` to plan outfits + their pieces (piece ordinals row-flat across the row) and report `UnappliedOutfit` / `UnappliedOutfitReason` (+ `PiecesRejected`)
- [x] 3.5 Rework `scene_beat_lanes` / `CostumeBeatSlot` into `OutfitBeatSlot` over `SceneApplyPlan.outfits`
- [x] 3.6 Unit tests: piece ordinals stay row-flat, category hint matching (hit/miss/case), outfit without pieces, rejected outfit ordinal, lane grouping per figure

## 4. Infra — schema-constrained extraction and prompt

- [x] 4.1 Replace `DraftCostumeSchema` with `DraftOutfitSchema` + `DraftPieceSchema` in `crates/infra/src/ai/client.rs` (wire field `outfits`)
- [x] 4.2 Update the structured-output schema assertions/tests that pin the costume field names
- [x] 4.3 Update the extraction call site to verify outfits (`verify_draft_outfits`) and record the uncertainty on field `outfits`
- [x] 4.4 Rewrite the `<costumes>` prompt section in `config/default_ai_prompts.toml` as `<outfits>`: evidence sources incl. shorthands (`KHK`, `OP`, `ITS`, uniforms), outfit naming, piece decomposition with German garment names and `Oberteil`/`Unterteil`/`Schuhe`/`Jacke`/`Accessoires` hints
- [x] 4.5 Keep the decision-model rubric (`costumes_complete`) working off the new dropped-outfit count

## 5. Infra — apply worker

- [x] 5.1 Add mapping kinds `piece` and `outfit`, `scene_outfit_beat`; drop `costume`
- [x] 5.2 Split `apply_costume` into `apply_piece` (CreatePiece → SetPieceCategory → UpdatePieceNotes, per-piece version chain) and `apply_outfit` (CreateOutfit with the outfit's piece ids)
- [x] 5.3 Reuse an already created piece on retry (`AddPieceToOutfit`/version recovery) instead of re-creating it
- [x] 5.4 Thread the outfit's piece ids into the beat dispatch and report outfit-level refusals
- [x] 5.5 Rename the result counters/fields (`created_outfits`, `created_pieces`, `unapplied_outfits`) and keep the beat counting rule
- [x] 5.6 Update `crates/infra/src/ai/tests.rs` and `worker_mutation_tests.rs` for the new shape (fakes, fixtures, assertions)

## 6. API — wire surface

- [x] 6.1 Load the target season's active `CostumeCategoryView` list in the apply handler and pass it into the planner (no write-side read)
- [x] 6.2 Rename the request field to `outfit_decisions` and the response field to `unapplied_outfits` in the handlers/DTOs
- [x] 6.3 Map outfit/piece error paths to the existing registered problem codes (no new standalone constants)
- [x] 6.4 Regenerate `openapi.yaml` (`UPDATE_OPENAPI=1 cargo test -p api --test contract openapi_drift`)
- [x] 6.5 Update `crates/api/src/handlers/ai_import_tests.rs` for the new request/response shapes

## 7. Flutter client — regenerated contract and review UI

- [x] 7.1 Regenerate the vendored client (`vendor/breakdown_api`) from `backend/openapi.yaml`
- [x] 7.2 Preview screen: render each draft outfit with its character, name, quoted source and its derived pieces (name + category hint)
- [x] 7.3 Apply screen: send `outfit_decisions` and render `unapplied_outfits` with the per-reason copy
- [x] 7.4 Update the affected widget/unit tests and Gherkin features for the outfit/piece shape
- [x] 7.5 `flutter analyze` + `flutter test` green

## 8. Verification

- [x] 8.1 `cargo test -p breakdown_core`, `-p infra`, `-p api` green
- [x] 8.2 `cargo clippy --workspace --all-targets -- -D warnings`
- [x] 8.3 `cargo test -p architecture_tests` + `cargo deny check bans`
- [x] 8.4 `cargo test -p api --test contract openapi_drift` green and `openspec validate ai-import-outfit-and-pieces`
