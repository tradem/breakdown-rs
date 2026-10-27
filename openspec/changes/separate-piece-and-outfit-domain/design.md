<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: gemini-4-argon (google) -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go)

# Design — Separate `Piece` and `Outfit` Domain Model

## Decisions

### D1 — Clean-Cut Separation: `Piece` (Fundus) vs. `Outfit` (Character Look)
Because `breakdown-rs` has no production event streams to preserve yet, we
avoid legacy replay shims (`Costume` aliases) and split the responsibilities
cleanly:

```
CostumeCategory (1) ◄──── (0..1) Piece (m) ◄────► (n) Outfit (n) ────► (1) Character
                                                        ▲
                                                        │ (1:n by ID)
                                                  SceneOutfitBeat
```

- **`PieceAggregate` (stream `"piece"`):**
  - Owns `id: PieceId`, `name: String` (non-empty), `category_id: Option<CostumeCategoryId>`,
    `seasons: Vec<SeasonId>`, `details: Vec<PieceDetail>`, `photos: Vec<Uuid>`,
    `notes: String`, `version: AggregateVersion`.
  - Has **no `character_id`**. Its domain scope is exclusively its `seasons`
    repertoire.
- **`OutfitAggregate` (stream `"outfit"`):**
  - Owns `id: OutfitId`, `character_id: CharacterId`, `name: String` (non-empty),
    `piece_ids: Vec<PieceId>` (`0..n`, ordered, deduplicated), `variant_of: Option<OutfitId>`,
    `photos: Vec<Uuid>`, `notes: String`, `version: AggregateVersion`.
  - Its domain scope is derived deterministically from `character_id → Character.season_id`.

### D2 — Layering and Empty-Shell Outfits (`0..n` Pieces)
- An `Outfit` may be created with `piece_ids: []` (`0` pieces) so wardrobe crews
  and AI import flows can establish named looks (e.g. `"Outfit 1: Büro"`,
  `"OP-Kleidung"`) or attach fitting photos before individual fundus pieces are
  cataloged.
- An `Outfit` imposes **no uniqueness constraint on `Piece.category_id`**:
  layering (e.g. T-shirt + dress shirt + sweater = 3× `Oberteil`, or multiple
  `Accessoires`) is a standard wardrobe requirement. Duplicate `piece_id`s
  within the same outfit are idempotently ignored (`AddPieceToOutfit` on an
  already-included piece is a state-based no-op).

### D3 — Continuity via ID Reference + Copy-on-Write Variants (`CreateOutfitVariant`)
- **Reference by identity:** Multiple `SceneOutfitBeat`s across scenes may
  reference the same `OutfitId` when a character wears the exact same look
  across consecutive scenes.
- **Minor cue:** Scene-specific wardrobe cues that do not alter the piece list
  (e.g. *"Kittel offen"*) are stored on `SceneOutfitBeat.note`.
- **Copy-on-Write Fork (`CreateOutfitVariant`):** When a scene requires a
  structural variation of an existing outfit:
  1. The API handler (the only legitimate read-model consumer per the CQRS
     boundary, `AGENTS.md §1`) reads the source `OutfitView` at the API edge.
  2. The handler dispatches `CreateOutfitVariant` to the new `OutfitAggregate`
     stream with `source_outfit_id`, `character_id`, `name`, and the initial
     `piece_ids` / `notes` (which the caller may already adjust or edit via
     subsequent commands).
  3. The aggregate emits `OutfitVariantCreated { id, source_outfit_id, character_id, name, piece_ids, notes, version: AggregateVersion::INITIAL }`.
  4. Write-side adapters and projectors never query `OutfitRepository` during
     command execution or replay.

### D4 — Shared Fitting Photos between `Outfit` and `Piece`
- In production workflows, garments are most often photographed during a
  character's outfit fitting rather than individually.
- Both `OutfitAggregate` and `PieceAggregate` support `PhotoLinked` /
  `PhotoUnlinked` for `PhotoId`.
- When a photo is uploaded to an `Outfit` (`PhotoBinding::Outfit { outfit_id }`),
  the upload handler (or an explicit link action) can also link the same
  `PhotoId` to the `PieceAggregate`s currently in `outfit.piece_ids`.
- Additionally, `PieceView` in the read model resolves both directly linked
  piece photos (`projection_piece_photo`) and outfit photos via
  `projection_outfit_piece ⋈ projection_outfit_photo` so a piece always has
  visual coverage even if the photo was only linked at the outfit level.
- `PhotoDeletionSaga` tracks in-memory refcounts across `Outfit`, `Piece`, and
  `SceneShoot` streams and only dispatches `DeletePhoto` when the combined
  reference count drops to `0`.

### D5 — Cross-Aggregate Invariants (`AGENTS.md §1` Doctrine)
| Invariant | Authoritative Backstop | API-Edge Pre-Check | Projector Behavior |
|---|---|---|---|
| `Piece.category_id` season match (`category.season_id ∈ piece.seasons`) | Best-effort `category_name` resolution (`None` on miss) | 404 `costume-category.not-found`, 409 `costume-category.archived`, 409 `costume-category.season-mismatch` | Never blocks or panics |
| `Outfit.character_id` exists in active season | Read-model join on `projection_character` | 404 `character.not-found`, 409 `season.archived` | Projector inserts `projection_outfit`; missing character yields `None` on joined character name |
| `Outfit.piece_ids` exist | Join table `projection_outfit_piece` (no FK to `projection_piece` that could fail on out-of-order stream replay) | 404 `piece.not-found` on `AddPieceToOutfit` / `CreateOutfit` | Idempotent upsert into `projection_outfit_piece` |
