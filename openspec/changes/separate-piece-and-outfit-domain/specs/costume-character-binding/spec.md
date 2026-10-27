<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go)

## REMOVED Requirements

### Requirement: Costume is scope-free
**Reason**: The `Costume` aggregate is split into two aggregates with
different responsibilities: `PieceAggregate` (fundus garment, no
`character_id`, repertoire-scoped — capability `piece-fundus`) and
`OutfitAggregate` (character-bound look — capability `outfit-management`).
The "scope-free" formulation described an aggregate that was simultaneously
the wardrobe item and the character's look, which is exactly the conflation
this change removes. The surviving rule (no production-scope **column**, read
model joins only) is restated, adapted to `Piece`, in `piece-fundus`.

**Migration**: `CreateCostume` → `CreatePiece { name, category_id, season_id }`
plus, when the former costume was bound to a character, `CreateOutfit
{ character_id, name, piece_ids: [piece_id] }`. No event alias or replay shim
is provided: no production streams exist, so retired `"costume"` streams are
inert.

### Requirement: Costume binding lives on character_id and category_id
**Reason**: The two bindings are now owned by different aggregates. The
character binding moved to `OutfitAggregate.character_id` (mandatory, exactly
one character per outfit, see `outfit-management`); the category binding
stayed on the garment and is now `PieceAggregate.category_id`
(`SetPieceCategory` / `PieceCategorySet`, see `piece-fundus` and
`costume-category`). The events
`CostumeAssignedToCharacter` / `CostumeUnassigned` are removed — an outfit is
created for its character and never re-bound; a new look for another character
is a new outfit (or a `CreateOutfitVariant` fork).

**Migration**: `AssignCostumeToCharacter` / `UnassignCostume` are replaced by
outfit creation/selection. `CostumeAssignedToCharacter` / `CostumeUnassigned`
events are not replayed; `SetCostumeCategory` becomes `SetPieceCategory`
against the piece stream. Cross-aggregate casting continues on the scene side
(`SceneOutfitBeat`).

### Requirement: An AI-created costume is created unassigned and then bound
**Reason**: An AI-imported garment no longer needs an owning character — the
piece is created in the fundus (optionally with an initial repertoire season)
and the AI apply path creates or reuses an `Outfit` for the extracted figure,
adding the piece to it (`AddPieceToOutfit`). The two-step
create-then-`AssignCostumeToCharacter` dance disappears, and with it the
partial-apply state where a costume existed unbound.

**Migration**: The AI import (`ai-costume-extraction`, successor change
`ai-import-outfit-and-pieces`) dispatches `CreatePiece` +
`UpdatePieceNotes` + (`CreateOutfit` | reuse by character name) +
`AddPieceToOutfit`. The successor change owns that rewrite; this change only
publishes the piece/outfit write model it needs.

### Requirement: Costume read model omits project_id
**Reason**: Superseded by the `piece-fundus` projection requirements. The
guarantee survives in substance — no production-scope column on the garment —
while the table is renamed and the `character_id` / `category_name` columns
change.

**Migration**: `projection_costume` → `projection_piece` (columns `id`,
`name`, `category_id`, `category_name`, `notes`, `version`, `updated_at`);
`projection_costume_season` → `projection_piece_season`;
`projection_costume_detail` → `projection_piece_detail`;
`projection_costume_photo` → `projection_piece_photo`. Old tables are dropped
in the same migration — no compatibility view is created.
