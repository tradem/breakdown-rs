<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: gemini-4-argon (google) -->

# AI Import Pass 1: Extract Character `DraftOutfit`s and Context-Derived `DraftPiece`s

## Why

With the domain separation into `Outfit` (character look per scene beat) and
`Piece` (individual fundus garment with category), the AI screenplay extraction
(Pass 1) must reflect how screenplays actually describe wardrobe:

- Screenplays either name a **standard/occupational outfit shorthand** (such as
  `KHK` for hospital gown, `OP` for surgical scrubs, `ITS` for intensive-care
  attire, police uniform, doctor's coat, paramedics) or describe a character's
  look in prose (e.g. *"im abgetragenen Bademantel und Gummistiefeln"*).
- Even when the screenplay only names the outfit shorthand (`"in OP"`), the
  wardrobe department needs the **constituent `Piece`s** (e.g. `"OP-Kasack"`,
  `"OP-Hose"`, `"OP-Haube"`) with their derived names and category hints
  (`Oberteil`, `Unterteil`, `Schuhe`, `Jacke`, `Accessoires`).
- Because screenplays vary widely in spelling (`"in OP"`, `"OP-Grün"`,
  `"Kasack"`, `"KHK"`, `"Flügelhemd"`), this decomposition must be driven by
  context-aware prompt rules in `default_ai_prompts.toml` rather than a brittle
  hardcoded glossary.

## What Changes

- **`core` (`crates/core/src/ai/preview.rs`):**
  - Replace `DraftCostume` with `DraftOutfit` + `DraftPiece`:
    - `DraftOutfit { character_name, name, notes, source_quote, origin, pieces: Vec<DraftPiece> }`
    - `DraftPiece { name, category_hint: Option<String>, description: Option<String> }`
  - **Grounded Outfit + Context-Derived Pieces (`verify_draft_outfits`):**
    - Explicit outfits (`DraftOutfitOrigin::ExplicitQuote`) continue to verify
      `source_quote` deterministically against the chunk text (anti-hallucination
      guard) and verify `character_name` against the scene's `characters`.
    - Once the `DraftOutfit` is grounded in the scene text, its `DraftPiece`s
      are permitted to carry context-derived names (e.g. deriving `"OP-Kasack"`
      and `"OP-Hose"` from `"in OP"`).
  - **Apply Planner (`plan_scene_apply`):**
    - Plans creation of the `Piece`s in the season's fundus (matching
      `category_hint` case-insensitively against the season's
      `CostumeCategory` vocabulary passed into the planner at the API boundary,
      leaving `category_id: None` on unknown hints), creates the character's
      `Outfit` referencing those `PieceId`s, and dispatches `AddOutfitBeat` on
      the `Scene`.
- **`infra` & `config/default_ai_prompts.toml`:**
  - Update the screenplay extraction schema and system prompt to instruct the
    LLM to:
    1. Extract `DraftOutfit`s per character (recognizing medical/occupational
       shorthands like `KHK`, `OP`, `ITS`, uniforms, and prose descriptions).
    2. Derive a concise outfit `name` and decompose the outfit into constituent
       `DraftPiece`s with German garment names and category hints (`Oberteil`,
       `Unterteil`, `Schuhe`, `Jacke`, `Accessoires`).

## Capabilities

### Modified Capabilities
- `ai-import`: Pass 1 extracts structured `DraftOutfit`s containing `0..n`
  context-derived `DraftPiece`s and applies them into `PieceAggregate`,
  `OutfitAggregate`, and `SceneOutfitBeat`.

## Impact

- **`crates/core/src/ai/`:** `DraftOutfit`, `DraftPiece`, `verify_draft_outfits`,
  `OutfitApplyPlan`, `PieceApplyPlan`.
- **`crates/infra/src/ai/` & `config/default_ai_prompts.toml`:** updated JSON
  schema and prompt instructions for outfit/piece extraction and shorthand
  interpretation (`KHK`, `OP`, `ITS`, occupational attire).
- **`crates/api`:** updated preview and apply wire shapes (`openapi.yaml` +
  client regen).
