<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: gemini-4-argon (google) -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go)

# Separate `Piece` (Fundus Garment) and `Outfit` (Character Look) in the Domain Model

## Why

Over the evolution of the wardrobe domain (`#453`/`#534` repertoire, `#543`
one-category, `#546` scene costume beats, `#625` fundus search), two distinct
domain concepts became conflated inside `CostumeAggregate`:

1. **The individual garment in the wardrobe fundus (`Piece` / Kleidungsstück):**
   Has a single garment category (`Oberteil`, `Unterteil`, `Schuhe`, `Jacke`,
   `Accessoires`), lives in the cross-season fundus repertoire (`seasons:
   Vec<SeasonId>`), and can be reused across outfits and seasons.
2. **The composed look worn by a character (`Outfit`):**
   Belongs to a specific `Character` (`character_id`), aggregates `0..n`
   `Piece`s (supporting layering such as multiple tops or accessories), carries
   fitting/look photos and notes, and is what is actually cast onto a character's
   beats within a `Scene` (`SceneOutfitBeat`).

Because `SceneCostumeBeat` referenced a single `Costume` while `Costume` was
restricted to a single garment category (`#543`), a character in a scene could
not wear a multi-garment outfit without abusing sequential scene beats (`order:
0, 1, 2`), which semantically represent in-scene costume changes (*"on change"*).

Because the system is not yet in production, we perform a **clean cut** (no
legacy event/projection shims): `Costume` is renamed to `Piece` (fundus item
without `character_id`), and `Outfit` is introduced as the character-bound
aggregation assigned to scene beats.

## What Changes

- **Clean-cut rename `Costume` → `Piece` (`crates/core/src/piece/`):**
  - `PieceAggregate` (stream category `"piece"`) represents a single wardrobe
    item in the fundus.
  - **Removes `character_id`:** a `Piece` belongs to the fundus (`seasons:
    Vec<SeasonId>`), never directly to a character.
  - **Adds required `name: String`** on `PieceAggregate` (resolving the
    `#543` follow-up to lift item identity onto the aggregate), alongside
    `category_id: Option<CostumeCategoryId>`, `seasons: Vec<SeasonId>`,
    `details: Vec<PieceDetail>`, `photos: Vec<Uuid>`, and `notes: String`.
- **New `OutfitAggregate` (`crates/core/src/outfit/`, stream category `"outfit"`):**
  - Bound to a mandatory `character_id: CharacterId` (inheriting its `SeasonId`
    scope via the character).
  - Carries `name: String` (e.g. `"Alltagslook Tag 1"`, `"OP"`, `"KHK"`),
    `piece_ids: Vec<PieceId>` (`0..n` pieces; an outfit may be created as an
    empty shell before pieces are assigned, and supports layering multiple
    pieces of the same category), `variant_of: Option<OutfitId>`,
    `photos: Vec<Uuid>`, `notes: String`, and `version: AggregateVersion`.
  - **First-class variant cloning (`CreateOutfitVariant` → `OutfitVariantCreated`):**
    Creates a new `OutfitAggregate` stream as an independent copy of a source
    outfit (`variant_of: Some(source_outfit_id)`), pre-populated with the
    source's `piece_ids` and `notes` (resolved at the API edge to preserve the
    CQRS boundary) so subsequent edits to the variant never mutate scenes that
    reference the original outfit.
- **Scene beats reference `OutfitId` (`SceneOutfitBeat`):**
  - `SceneAggregate.outfit_beats: Vec<SceneOutfitBeat>` replaces `costume_beats`,
    carrying `{ character_id, outfit_id, order, note }`.
  - Multiple scenes may reference the same `outfit_id` for continuity; scene-local
    deviations are expressed either via `SceneOutfitBeat.note` or by forking a
    variant via `CreateOutfitVariant` and updating the beat's `outfit_id`.
- **Shared photo references between `Outfit` and `Piece` (`photo` context):**
  - Both `OutfitAggregate` and `PieceAggregate` link `PhotoId`s (`PhotoLinked` /
    `PhotoUnlinked`). Because individual pieces are frequently only photographed
    as part of an outfit fitting, a photo uploaded to an `Outfit` can also be
    linked to its constituent `Piece`s (and `PieceView` surfaces outfit fitting
    photos alongside direct piece photos).
  - `PhotoDeletionSaga` tracks reference counts across `Outfit`, `Piece`, and
    `SceneShoot` streams before dispatching `DeletePhoto`.

## Capabilities

### New Capabilities
- `outfit-management`: `OutfitAggregate` lifecycle (`CreateOutfit`,
  `CreateOutfitVariant`, `UpdateOutfitName`, `UpdateOutfitNotes`,
  `AddPieceToOutfit`, `RemovePieceFromOutfit`, `LinkOutfitPhoto`,
  `UnlinkOutfitPhoto`), projections, and HTTP routes.
- `piece-fundus`: `PieceAggregate` (renamed from `CostumeAggregate`, without
  `character_id`, with first-class `name`, single `category_id`, and season
  repertoire).

### Modified Capabilities
- `scene-costume-assignment`: updated to assign `OutfitId` (`SceneOutfitBeat`)
  per `(scene_id, character_id, order)` instead of `CostumeId`.
- `costume-category`: categories classify `Piece`s in the fundus (`1 Piece =
  0..1 CostumeCategory`).

## Impact

- **`crates/core`:** `costume` replaced by `piece` + `outfit`; `scene` beat
  commands/events/views updated to `outfit_id`; `photo::PhotoBinding` updated
  for `Outfit` and `Piece`.
- **`crates/infra`:** clean-cut projection schema (`projection_piece`,
  `projection_piece_season`, `projection_piece_detail`, `projection_piece_photo`,
  `projection_outfit`, `projection_outfit_piece`, `projection_outfit_photo`,
  `projection_scene_outfit_assignment`); projectors, repositories, command
  adapters, and `PhotoDeletionSaga`.
- **`crates/api`:** `/v1/pieces` and `/v1/outfits` (and `/v1/characters/{id}/outfits`)
  routes, `openapi.yaml` and vendored client regeneration.
