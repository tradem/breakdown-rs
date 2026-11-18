<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: gemini-4-argon (google) -->

# AI Import Pass 2: Decision-Model Cross-Scene Outfit Continuity & Gap Analysis

## Why

In production screenplays, wardrobe is typically mentioned only when a character
first appears in a setting or changes clothes. Subsequent scenes at the same
location or on the same `script_day` rarely repeat the costume description, even
though the character is actively participating in the scene.

After Pass 1 (chunk extraction) completes, many `(scene, character)` pairs have
a plausible scene action (`summary` / scene body) and assigned characters, but
**no extracted outfit**. We need a second, cross-scene AI pass that inspects
every such `(scene, character)` gap and uses the **Decision Model** (`#722`) to
determine the most probable wardrobe state:

- **Option A — Continuation (`ContinuePrevious`):** The character continues
  wearing the outfit from the preceding scene(s) (referencing the same
  `OutfitId` on apply).
- **Option B — New Context-Derived Outfit (`InferNewOutfit`):** The scene
  context (e.g. a location shift into `"OP-SAAL"` or `"INTENSIVSTATION"`, or a
  new `script_day`) implies a new outfit derived from the scene context.
- **Option C — Conflict / Unresolved Gap (`ReportConflictOrGap`):** The context
  is ambiguous or provides no basis for an automatic decision, surfacing an
  `Uncertainty` for human review. Selectable options in the preview are offered
  **only** when concrete candidates are actually derivable from the script.

## What Changes

- **`core` (`crates/core/src/ai/`):**
  - Extend `DraftOutfitOrigin` with:
    - `ExplicitQuote { source_quote: String }` (Pass 1)
    - `ContinuedFromScene { source_draft_ref: String, source_scene_number: Option<u32>, confidence: f32 }` (Pass 2, Option A)
    - `InferredFromContext { confidence: f32 }` (Pass 2, Option B)
  - Define the Pass 2 candidate eligibility gate: a `(DraftScene, DraftCharacter)`
    pair is eligible for Pass 2 **only if**:
    1. The character has no `DraftOutfit` in that scene after Pass 1, **AND**
    2. The scene has plausible action (`summary` is present and passes
       `!is_meta_summary`, or the chunk body contains substantive action beyond
       a bare heading/outline stub).
  - Define Decision Model question builders (`decision.rs`) for Pass 2:
    - Evaluates the structured continuity state (current scene heading, location,
      `mood`, `script_day`, `summary`, plus the character's previous outfit(s)
      and scene context) via `DecisionQuestion::Choice` over Options A, B, and C.
  - Extend `Uncertainty` (or candidate metadata on `Uncertainty`) so Option C
    surfaces **script-derivable candidate options** in the preview **only** when
    candidates actually exist in the script (e.g. a prior scene's outfit vs. a
    context-inferred outfit); when no candidate can be derived from the script,
    a plain gap uncertainty is recorded without fabricated choices.
- **`infra` (`crates/infra/src/ai/`):**
  - Run Pass 2 in `ScriptImportWorker` after all chunks are extracted and merged:
    - **Option A winner:** attaches a `DraftOutfit` referencing the prior
      scene's outfit (`ContinuedFromScene`) so `plan_scene_apply` binds the
      scene's `SceneOutfitBeat` to the **same `OutfitId`** (DDD reference by
      identity, no duplicate `OutfitAggregate`).
    - **Option B winner:** derives the new `DraftOutfit` + `DraftPiece`s from
      the scene context (`InferredFromContext`).
    - **Option C winner (or low confidence / no candidates):** emits an
      `Uncertainty` on the scene with only the candidates genuinely derivable
      from the script.

## Capabilities

### New Capabilities
- `ai-import-outfit-continuity-pass`: Post-extraction cross-scene scan and
  Decision Model evaluation (Options A / B / C) for characters in scenes with
  plausible action but no explicit outfit.

### Modified Capabilities
- `ai-import`: Preview and apply planner support `ContinuedFromScene`
  (shared `OutfitId` reference across scenes), `InferredFromContext`, and
  script-grounded candidate resolution on Option C uncertainties.

## Impact

- **`crates/core/src/ai/preview.rs` & `decision.rs`:** Pass 2 eligibility scan,
  Decision Model state/question builders, `DraftOutfitOrigin`, shared
  `OutfitId` planning for `ContinuedFromScene`, and Option C uncertainty
  candidates.
- **`crates/infra/src/ai/`:** `ScriptImportWorker` Pass 2 orchestration
  (best-effort / non-fatal, owner-fenced under the existing job lease).
- **`crates/api` & `frontend-flutter`:** Preview UI displays provenance badges
  (explicit vs. continued vs. inferred) and renders selectable candidates on
  Option C uncertainties only when script-derived candidates exist.
