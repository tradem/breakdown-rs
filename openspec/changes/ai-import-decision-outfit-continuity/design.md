<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: gemini-4-argon (google) -->

# Design — AI Import Pass 2: Decision-Model Outfit Continuity & Gap Analysis

## Decisions

### D1 — Plausible-Action Eligibility Gate
Outline stubs, empty scene headers, or meta-summaries (`"Keine Handlung im Block"`)
must never trigger outfit inference or false conflict uncertainties.
A `(scene_index, character_identity)` gap enters Pass 2 if and only if:
1. `character_identity` is in `scene.characters`,
2. no `DraftOutfit` in `scene.outfits` matches `character_identity`, and
3. `scene.summary` is `Some(s)` with `!s.trim().is_empty()` and
   `!is_meta_summary(&s)`.

### D2 — Decision Model Evaluation (Option A vs. Option B vs. Option C)
For each eligible `(scene_index, character_identity)` gap, the worker builds a
compact, deterministic continuity state containing:
- **Current scene:** `scene_number`, `location`, `mood`, `script_day` /
  `shooting_day`, `summary`, and the character's action lines in the chunk.
- **Prior appearance(s) of the same character:** most recent scene with an
  outfit (`scene_number`, `location`, `mood`, `script_day`, `outfit.name`,
  `outfit.pieces`).

The Decision Model (`DecisionClient`, issue `#722`) evaluates a calibrated
categorical question (`DecisionQuestion::Choice`):
- **`continue_previous` (Option A):** The character continues wearing the prior
  scene's outfit (only valid when a prior outfit exists in the script).
- **`infer_new_outfit` (Option B):** The scene's location/action implies a new
  outfit that can be derived from the scene context (e.g. entering an operating
  room `"OP"`, intensive care `"ITS"`, changing day/time/setting).
- **`report_conflict_or_gap` (Option C):** Neither continuation nor new
  inference is sufficiently certain, or both compete (e.g. a day change at the
  same workplace).

### D3 — Referencing Shared `OutfitId` on Option A (`ContinuedFromScene`)
When Option A wins:
- The `DraftOutfit` in scene `S` carries
  `DraftOutfitOrigin::ContinuedFromScene { source_draft_ref, source_scene_number, confidence }`.
- During `plan_scene_apply`, no second `OutfitAggregate` or duplicate `Piece`s
  are created. Instead, the apply worker resolves the `OutfitId` created for
  `(source_draft_ref, character_identity)` from `ai_import.apply_mapping` and
  dispatches `AddOutfitBeat` on scene `S` referencing that **exact same
  `OutfitId`**.

### D4 — Option C Uncertainties: Choices Only When Script-Derivable
Per Product Owner requirement, the preview UI must never present invented
multiple-choice options when the script offers no basis for them:
- **Case C1 — Competing script-derivable candidates exist** (e.g. Candidate 1:
  continuation of prior outfit `"Zivil-Look"` from Scene 4; Candidate 2:
  context-derived `"OP-Kleidung"` from Scene 5's `"I/T - OP-SAAL"` location):
  The `Uncertainty` carries those concrete `candidates: Vec<DraftOutfitCandidate>`
  so the reviewer can pick one (or choose "leave empty") in the preview.
- **Case C2 — No candidate is derivable from the script** (e.g. the character's
  very first appearance occurs in a generic corridor with zero wardrobe clues):
  `candidates` is empty (`[]`). The reviewer sees a simple gap notification
  that can be acknowledged with one tap (`#663`), leaving the scene without an
  outfit until wardrobe planning assigns one manually.
