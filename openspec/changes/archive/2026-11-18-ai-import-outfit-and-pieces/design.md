<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: gemini-4-argon (google) -->

# Design — AI Import Pass 1: `DraftOutfit` and Context-Derived `DraftPiece`s

## Decisions

### D1 — Two-Level Extraction Shape: Grounded `DraftOutfit` + Derived `DraftPiece`s
Screenplays rarely enumerate every garment of a standard look (*"OP-Kasack,
OP-Hose, OP-Schuhe"*); they state `"DR. KOCH (in OP)"` or `"PATIENT (in KHK)"`.
If the server enforced verbatim substring grounding on each individual `Piece`
name, derived pieces for `"in OP"` would be rejected as `UngroundedQuote`.

Therefore, grounding operates at the **Outfit** level:
- `DraftOutfit` carries `source_quote: String` (for `DraftOutfitOrigin::ExplicitQuote`).
- `verify_draft_outfits` verifies that `outfit.source_quote` appears in
  `chunk_text` (whitespace/case-folded) and that `outfit.character_name`
  matches a character of the scene.
- `DraftOutfit.pieces: Vec<DraftPiece>` contains `0..n` context-derived pieces
  (`{ name: String, category_hint: Option<String>, description: Option<String> }`).
  Because the parent `DraftOutfit` is grounded in the text, the LLM is free to
  derive sensible piece names from context when the script only names an outfit
  shorthand (`KHK`, `OP`, `ITS`, occupational attire) or a broad look.

### D2 — Prompt-Driven Shorthand Interpretation (No Rigid Glossary)
Instead of a hardcoded Rust dictionary that breaks on spelling variations
(`"OP"`, `"OP-Grün"`, `"OP-Kleidung"`, `"Bereichskleidung"`, `"KHK"`,
`"Flügelhemd"`, `"ITS"`), `config/default_ai_prompts.toml` defines the domain
decomposition rules and examples:
- When a medical/occupational shorthand or role attire is mentioned in the
  scene, extract a `DraftOutfit` with a clear display name and decompose it into
  its typical constituent `DraftPiece`s with `category_hint` values from the
  canonical category set (`Oberteil`, `Unterteil`, `Schuhe`, `Jacke`,
  `Accessoires`).
- When the outfit is not explicitly named by a shorthand, derive descriptive
  names for both the `DraftOutfit` and its `DraftPiece`s from the scene context.

### D3 — CQRS-Safe Apply Planning for `Piece`, `Outfit`, and `SceneOutfitBeat`
To respect the CQRS boundary (`AGENTS.md §1`), the write-side apply worker never
queries projections:
1. At the API boundary (`apply_ai_import`), the handler loads the target
   season's active `CostumeCategoryView` list and passes the `(name →
   CostumeCategoryId)` map into the pure planner `plan_scene_apply`.
2. For each accepted `DraftOutfit`:
   - Each `DraftPiece` is planned as `CreatePiece` (with `season_id` seeding its
     fundus repertoire) + optional `SetPieceCategory` (when `category_hint`
     matches an active category of the season) + optional `UpdatePieceNotes`.
   - Within the same preview, identical piece definitions for the same character/outfit
     can be deduplicated by normalized `(name, category_hint)` key via the
     idempotent apply mapping table (`ai_import.apply_mapping`).
   - The `Outfit` is planned as `CreateOutfit { id, character_id, name, piece_ids, notes }`.
   - The scene beat is planned as `AddOutfitBeat { scene_id, character_id, outfit_id, note: None }`.
