<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3 (neuralwatt) -->

# 739 — Piece + Outfit Wardrobe Frontend (screens, navigation, copy)

## Why

Issue #739. The backend change `separate-piece-and-outfit-domain` (PR #740)
split `Costume` into `Piece` (the fundus garment) and `Outfit` (the character's
composed look) with a clean cut: `/v1/costumes*` routes are gone (404),
`SceneCostumeBeat` became `SceneOutfitBeat`, `PhotoBinding::Costume` became
`Piece` + `Outfit`, and the `costume.*` problem codes were retired.

PR #740 carried the *compile-level* port (task 7.7 of that change): the
regenerated client, drift cache v16 with `piece_cache_rows` /
`outfit_cache_rows`, `PieceRepository` + `OutfitRepository`, the wardrobe list
and detail screens re-typed onto `PieceView`, and the scene beat picker on
`OutfitView`. `flutter analyze` is clean and `flutter test` is 1853/1853.

What that port deliberately left open (task 7.8) is the **presentation layer**:

1. **No outfit UI exists.** `characterOutfitsProvider` is consumed only by the
   scene-casting picker, so a character's looks can be cast but never
   *managed*: no list, no detail, no create/variant/rename/notes, no piece
   add/remove, no fitting photos, no zero-`outfit*` copy keys. Issue item 4 is
   unimplemented.
2. **Dead photo routes.** `PhotoRepository.upload()` still POSTs
   `/v1/costumes/{id}/photos`, which now answers 404, and there is no outfit
   photo path at all — continuity capture and piece photos are broken at
   runtime while the compiler stays silent (raw `Dio` path, not the generated
   client).
3. **Costume vocabulary** survives in `lib/features/costumes/**` (~6.3k lines,
   `CostumeRow`/`CostumesScreenState`/`costumeTileIdentity`, …), in ~53 German
   copy keys ("Kostüm"), in `docs/design/screens/costumes.md`, and in
   `docs/design/glossary.md`, which never received the Piece/Outfit terms the
   backend change assumed. The AI-import draft vocabulary
   (`DraftCostume`/`PreviewCostume`) is **out of scope** — its own successor
   changes (`ai-import-outfit-and-pieces`, `ai-import-decision-outfit-continuity`)
   own it.
4. **No frontend OpenSpec artifact and no design spec** cover the split, so
   `flutter-ci.yml` has nothing to gate the new behaviour against and the
   `docs/design/screens/` set documents a retired model.

## What Changes

- **Design docs first** (AGENTS.md §11): `docs/design/screens/costumes.md`
  becomes `docs/design/screens/pieces.md` (Kleidungsstück catalogue, no
  character binding), new `docs/design/screens/outfits.md` (per-character
  Looks), and the glossary gains the `Kleidungsstück` (Piece) / `Look`
  (Outfit) terms plus their copy keys; cross-references in the neighbouring
  specs are re-termed. Every PlantUML block stays compilable.
- **Outfit feature** (`lib/features/outfits/`): `OutfitListSection` in the
  character detail screen (name, variant lineage, piece count) and an
  `OutfitDetailScreen` (rename, notes, ordered piece rows with add/remove,
  fitting photos, `Variante erstellen`, delete-free by design). Controller
  state mirrors the seasons reference pattern: Drift-cached projection,
  optimistic overlay on 2xx, version-fence clearing, bounded-retry resync.
- **Piece ↔ outfit navigation:** an outfit's piece row opens the piece detail
  of the same season; the piece detail links back to the characters whose
  looks contain it through the character detail's outfit list. No second
  projection lookup fills a command (CQRS boundary, AGENTS.md §1).
- **Photo bindings repaired:** `PhotoRepository` uploads/deletes/fetches on
  `/v1/pieces/{id}/photos` and gains the `/v1/outfits/{id}/photos` trio; the
  watch stream is generic over the enriched view (piece **or** outfit) so the
  outfit detail reuses the same bounded-backoff reconciliation instead of a
  second polling implementation.
- **Full presentation rename:** `lib/features/costumes/` → `lib/features/pieces/`
  (`CostumeRow` → `PieceRow`, `CostumesScreenState` → `PiecesScreenState`,
  `costumeTileIdentity` → `pieceTileIdentity`, …), copy keys `costume*` →
  `piece*` (the `costumeCategory*` vocabulary keys, the `assign_costumes`
  capability and `hasActiveCostumeRoleInSeries` stay exactly as-is — issue
  item 5), scene-beat copy `sceneDetail*Costume*` → `sceneDetail*Outfit*`,
  and the German labels move to "Kleidungsstück" / "Look".
- **Gherkin + tests:** the outfit-casting flow replaces costume assignment as
  the designated critical scenario, the integration seed helper seeds pieces
  and outfits, and the new screens ship unit + widget + golden coverage so the
  80 % gate holds.

## Non-goals

- The AI-import draft vocabulary (`DraftCostume`, `PreviewCostume`,
  `costumeDecision`, `aiPreviewCostume*`) — owned by the sibling changes.
- The `costume-category` aggregate, its routes and its copy: the division's
  vocabulary is unchanged by the split.
- Backend changes of any kind: `backend/openapi.yaml` and the vendored client
  are inputs, not outputs, of this change (the drift job only verifies them).
- An offline command queue for outfit writes (AGENTS.md §8 scope).
