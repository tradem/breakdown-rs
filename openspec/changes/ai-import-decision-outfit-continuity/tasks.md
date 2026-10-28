<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

# Tasks — AI Import Pass 2: Decision-Model Outfit Continuity

## 1. Core — provenance data model

- [x] 1.1 Extend `DraftOutfitOrigin` (`crates/core/src/ai/preview.rs`) with `ContinuedFromScene { source_draft_ref, source_scene_number, confidence }` and `InferredFromContext { confidence }`; keep the unit variants `ExplicitQuote` / `Derived`, drop the now-invalid `Copy` derive
- [x] 1.2 Add `DraftOutfitCandidate { origin, name, source_draft_ref, source_scene_number, confidence }` (`Serialize`/`Deserialize`/`ToSchema`) and `Uncertainty.candidates: Vec<DraftOutfitCandidate>` (`serde(default)` — additive wire rule)
- [x] 1.3 Re-export the new type from `crates/core/src/ai/mod.rs`

## 2. Core — eligibility gate and continuity evaluation

- [x] 2.1 `outfit_continuity_gaps(&ScriptContext) -> Vec<OutfitContinuityGap>` implementing design D1: character named by the scene, no outfit for that identity, `summary` present/non-blank/`!is_meta_summary`
- [x] 2.2 `prior_outfit(preview, scene_index, identity)` — the character's most recent earlier scene carrying an outfit, with its scene
- [x] 2.3 `continuity_state(preview, gap)` (design D2 state payload) and `continuity_questions()` + `question_keys::OUTFIT_CONTINUITY` in `crates/core/src/ai/decision.rs` (one `DecisionQuestion::Choice` over `continue_previous` / `infer_new_outfit` / `report_conflict_or_gap`)
- [x] 2.4 `context_look_name(scene) -> Option<String>` — deterministic label from the scene's own location (never model text)
- [x] 2.5 `resolve_continuity_outcome(...)` — highest-probability AVAILABLE option, `continue_previous` unavailable without a prior outfit, `CONTINUITY_MIN_CONFIDENCE` threshold constant
- [x] 2.6 `continuity_candidates(gap, prior, scene)` — only continuation and (on a location shift / day change) the context look; empty when nothing is derivable
- [x] 2.7 Unit tests: the three gate rejections, option fallback without a prior outfit, threshold, zero/one/two candidates, most-recent-prior selection

## 3. Core — apply planner: continuation and candidate selection

- [x] 3.1 `ContinuationPlan { source_draft_ref, source_outfit_ordinal, source_character_identity }` and `OutfitApplyPlan.continuation: Option<ContinuationPlan>`
- [x] 3.2 `plan_scene_apply` plans a `continued_from_scene` row with **no** pieces (source resolved from the immutable preview), reports `UnappliedOutfitReason::ContinuityUnresolved` when the source row/outfit cannot be resolved
- [x] 3.3 `OutfitContinuitySelection { scene_index, character_identity, candidate }` + `ReviewerDecisions.continuity_selections`; validate a selection against the preview's candidate list and plan it as an outfit row of its scene
- [x] 3.4 Unit tests: continuation source ordinal resolved, unresolvable continuation reported, selection plans a continued row, selection plans an inferred row, unknown selection refused, no selection plans nothing

## 4. Infra — Pass 2 runner

- [x] 4.1 New module `crates/infra/src/ai/outfit_continuity.rs`: `run_outfit_continuity_pass(pass, preview, usage, claim_lost)` — one decision request per eligible gap, best-effort, stops on claim loss
- [x] 4.2 Apply Option A (attach `ContinuedFromScene` outfit), Option B (attach `InferredFromContext` label look + non-blocking uncertainty), Option C / low confidence (non-blocking gap uncertainty with candidates)
- [x] 4.3 Wire the pass into `ScriptImportWorker::process_text` after the chunk loop, before the category-conflict collection and the preview store; any failure logs and continues
- [x] 4.4 Register the module in `crates/infra/src/ai/mod.rs`
- [x] 4.5 Tests with a fake `DecisionClient`: Option A, Option B, Option C, decision failure leaves the preview unchanged, claim lost stops the pass, no decision pass is a no-op

## 5. Infra — apply worker: shared `OutfitId`

- [x] 5.1 In `ApplyWorker::apply_script`, a slot whose outfit carries a `ContinuationPlan` resolves the SOURCE outfit's aggregate id from the apply mapping and dispatches only the beat — no piece create, no outfit create
- [x] 5.2 Report `UnappliedOutfitReason::ContinuityUnresolved` when the source mapping row is missing or never reached its create
- [x] 5.3 Tests: two scenes share one `Outfit` aggregate, retry adds no second outfit/beat, rejected source reported with the continuation reason

## 6. API — wire contract

- [x] 6.1 `ApplyAiImportRequest.continuity_selections` (`serde(default)`) → `ReviewerDecisions.continuity_selections`
- [x] 6.2 New problem code `AI_IMPORT_APPLY_UNKNOWN_CONTINUITY_CANDIDATE` (`ai-import.apply-unknown-continuity-candidate`, 409, extension `draft_ref`) in `crates/core/src/error_registry.rs` + Fluent text in `crates/api/locales/{en,de}/errors.ftl`; the handler answers it for a stale selection
- [x] 6.3 Handler test: a selection the preview does not offer is refused with that code, nothing dispatched
- [x] 6.4 Regenerate `backend/openapi.yaml` (`UPDATE_OPENAPI=1 cargo test -p api --test contract openapi_drift`)

## 7. Docs and follow-up

- [x] 7.1 `backend/CHANGELOG.md` `[Unreleased]` entry
- [x] 7.2 Record the two deviations from `proposal.md` in `design.md` (additive origin shape; Option B derives a label only, never garments)
- [x] 7.3 GitHub issue (English) for the Flutter follow-up: provenance badges, candidate picker, Dart client regen — referencing this OpenSpec change and `/opsx-apply ai-import-decision-outfit-continuity` → issue #745
- [x] 7.4 Regenerate the Dart client (`frontend-flutter/scripts/regen-client.sh`) so the committed tree matches the new contract (`flutter analyze` clean, `flutter test test/features/ai_import` green); the UI work itself stays in #745

## 8. Verification

- [x] 8.1 `cargo test -p breakdown_core -p infra -p api`
- [x] 8.2 `cargo clippy --workspace --all-targets -- -D warnings`
- [x] 8.3 `cargo test -p architecture_tests` + `cargo deny check bans`
- [x] 8.4 `cargo test -p api --test contract openapi_drift` and `openspec validate ai-import-decision-outfit-continuity`

## 9. Review findings (PR #746, CodeRabbitAI)

- [x] 9.1 **Wire contract:** the origin stays a plain string enum
  (`DraftOutfitOrigin::{ExplicitQuote, Derived, ContinuedFromScene,
  InferredFromContext}`) and the Pass-2 payload moved to
  `DraftOutfit.provenance: Option<DraftOutfitProvenance>` — the mixed enum made
  the generated Dart client undecodable (`more than one match found`), proven
  with a probe test, now covered by a real Flutter test
- [x] 9.2 **Beat addressing:** `OutfitApplyPlan.beat_ordinal` is computed by the
  planner from the immutable preview; selected gap rows carry
  `from_continuity_selection` and their own mapping kinds — regression tests
  `accepting_a_previously_rejected_outfit_keeps_every_beat_address` and
  `a_continuity_selection_keeps_its_address_when_others_are_added`
- [x] 9.3 **Selection validation:** indexed gaps, one ordered preview sweep for
  prior outfits, set-based duplicate detection, and an in-pass count guard
- [x] 9.4 Stale task references corrected (`ContinuationUnresolved` →
  `ContinuityUnresolved`)
