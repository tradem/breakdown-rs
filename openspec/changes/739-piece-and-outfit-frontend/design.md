<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3 (neuralwatt) -->

# Design — Piece + Outfit Wardrobe Frontend

## Decisions

### D1 — Two aggregate folders, one navigation tree

`lib/features/pieces/` (renamed from `costumes/`) owns the fundus garment and
`lib/features/outfits/` owns the character's composed look. AGENTS.md §1/§2
maps one feature folder to one aggregate boundary, and the split is exactly
that boundary: a piece has no character, an outfit has no repertoire. The
wardrobe list is still one screen (season scope, `GET /v1/pieces?season_id=`),
because splitting it would duplicate the same fetch, cache slice and category
picker.

Consequence: the outfit list is **not** a wardrobe tab. It lives in the
character detail screen (`_OutfitsSection` beside `_ContactSection` /
`_MeasurementsSection`), because "which looks does this character have" is a
character question, and the created look's mandatory `character_id` comes from
that screen's own read DTO — never from a second projection lookup (CQRS
boundary, AGENTS.md §1).

### D2 — Presentation naming follows the domain (full rename)

The compile-level port kept `CostumeRow`, `CostumesScreenState`,
`costumeTileIdentity`, `lib/features/costumes/` and ~53 `costume*` copy keys
while the DTOs underneath were already `PieceView`. Two vocabularies for one
concept is the drift AGENTS.md §1 warns about, and it is what makes a reviewer
re-introduce `assign`/`unassign` by reflex. This change renames the
presentation layer end to end:

| before | after |
|---|---|
| `lib/features/costumes/{costumes_screen,costume_detail_screen,costumes_controller,costumes_state,costume_identity}` | `lib/features/pieces/{pieces_screen,piece_detail_screen,pieces_controller,pieces_state,piece_identity}` |
| `CostumeRow`, `ProjectedCostumeRow`, `OptimisticCostumeRow`, `CostumeRowOverlay` | `PieceRow`, `ProjectedPieceRow`, `OptimisticPieceRow`, `PieceRowOverlay` |
| `CostumesScreenState`, `CostumesViewController`, `CostumesCommandError` | `PiecesScreenState`, `PiecesViewController`, `PiecesCommandError` |
| `CostumeTileIdentity`, `costumeTileIdentity`, `costumeDisplayName` | `PieceTileIdentity`, `pieceTileIdentity`, `pieceDisplayName` |
| `costumeRepositoryProvider`, `costumesViewProvider`, `costumePhotoRepositoryProvider` | `pieceRepositoryProvider`, `piecesViewProvider`, `piecePhotoRepositoryProvider` |
| `navCostumes`, `costumeAddFab`, `costumesEmpty`, `costumeTileLabel*`, `costumeError*`, `costumeDetail*` (except category) | `navWardrobe`, `pieceAddFab`, `piecesEmpty`, `pieceTileLabel*`, `pieceError*`, `pieceDetail*` |
| `sceneDetailCostumesTitle`, `sceneDetailAssignCostume`, `sceneDetailPickCostumeTitle`, `sceneDetailCostumeCueHint`, `sceneDetailRemoveCostume*`, `sceneDetailNoCostumeInScene` | `sceneDetailOutfitsTitle`, `sceneDetailAssignOutfit`, `sceneDetailPickOutfitTitle`, `sceneDetailOutfitCueHint`, `sceneDetailRemoveOutfit*`, `sceneDetailNoOutfitInScene` |
| `seasonsMetaCostumes`, `scriptRowCostumes`, `omniSearchChipCostume`, `omniSearchGroupCostumes` | `seasonsMetaPieces`, `scriptRowOutfits`, `omniSearchChipPiece`, `omniSearchGroupPieces` |
| `continuityCostumeHint` | `continuityPieceHint` |

**Deliberately unchanged** (issue item 5 and the sibling changes' scope):
`costumeCategory*` identifiers and copy (the category aggregate did not
split), `assign_costumes` (capability string), `costumeMembershipScope` /
`hasActiveCostumeRoleInSeason` / `hasActiveCostumeRoleInSeries` (role
predicates, wire names), `blocksRoleCostume` ("Kostüm-Rolle"), and the
AI-import draft vocabulary (`DraftCostume`, `PreviewCostume`,
`CostumeDecision`, `aiPreviewCostume*`, `aiApplyUnappliedCostume`).

The rename is mechanical (identifier + file moves + ARB key renames), so it is
one reviewable commit with `dart format` and the golden baselines regenerated —
no behaviour change rides along.

### D3 — Outfit controller state mirrors the seasons reference pattern

`OutfitListState` holds `AsyncValue<List<OutfitView>>` (Drift-cached,
character-scoped) plus ephemeral `OutfitRowOverlay`s. A command
acknowledgement with version *v* installs an overlay; the overlay is dropped
by `shouldClearOutfitOverlay(projection: row, acknowledgedVersion: v)`, i.e.
the **version fence** — the same rule as `shouldClearCostumeOverlay`. An
out-of-order/stale projection therefore cannot clobber an acknowledged edit,
and the overlay never enters Drift.

Reconciliation is the bounded-retry refetch of the affected slice (bounded
attempts + fake-clock budget in tests, never `Future.delayed` wall clock).
Variant creation navigates to the fork after the 2xx and leaves the source
list entry untouched.

Photo variants reuse `PhotoRepository`'s bounded watch, generalized to
`watch<View>` with an injected terminal predicate: `isPhotoWatchTerminal`
(piece) and `isOutfitPhotoWatchTerminal` (outfit) are the only two
specializations, so no second polling loop exists.

### D4 — Piece ↔ outfit navigation without a cross-aggregate fetch

The outfit detail's piece rows carry `OutfitPieceView { pieceId, position,
name, category_id, category_name }` joined by the backend. Tapping a row
pushes the piece detail with the piece id and the outfit's `season_id`; the
piece detail resolves the row from the already-watched season projection
(`piecesViewProvider`) and, when the row is absent, renders the joined
category name plus a not-found surface — never a UUID, never a throw.

The reverse direction is the character detail's outfit section: the piece
detail does **not** call an outfit route to answer "where is this used",
because `PieceView` exposes no outfit membership and deriving one from a
second projection call would be the CQRS-boundary violation AGENTS.md §1
forbids. The affordance is a navigation shortcut to the cast/character
screens, not a derived command payload.

### D5 — Photo bindings are route-correct and single-sourced

`PhotoRepository` switches to the split routes through the generated client
(`uploadPiecePhoto` / `uploadOutfitPhoto`, `deletePiecePhoto` /
`deleteOutfitPhoto`, `getPiecePhotoBytes` / `getOutfitPhotoBytes`). The raw
`Dio` upload path stays (the generated client types the body as `String`,
which cannot carry binary), but the path template is now
`/v1/pieces/{id}/photos` — the retired `/v1/costumes/{id}/photos` literal was
a 404 that no compiler could catch. A regression test asserts the recorded
request path, so the mistake cannot return silently.

### D6 — Gherkin: outfit casting replaces costume assignment

AGENTS.md §6 designates *costume assignment* as a business-critical Gherkin
flow. Its domain meaning is now *outfit casting*: cast a look onto a scene
beat, reuse the same `outfit_id` for continuity, deviate through
`CreateOutfitVariant`. The existing scene-beat feature keeps its steps but
seeds pieces + outfits (the integration seed helper posts
`/v1/pieces` and `/v1/outfits` instead of `/v1/costumes`), and the outfit-list
flow is added as a widget/unit tier concern only — a `.feature` file whose
steps only exercise pure functions is explicitly out of bounds (AGENTS.md §6).
