<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3 (neuralwatt) -->

# Tasks — Piece + Outfit Wardrobe Frontend

## 1. Design docs (before implementation, AGENTS.md §11)

- [x] 1.1 Rename `docs/design/screens/costumes.md` → `docs/design/screens/pieces.md`; rewrite for the fundus garment (no character binding, no assign/unassign, repertoire + category + details + photos, piece↔outfit navigation entry); keep the Salt block compilable.
- [x] 1.2 Author `docs/design/screens/outfits.md` (list section in the character detail + outfit detail: name, variant lineage, ordered pieces, fitting photos, notes, `Variante erstellen`).
- [x] 1.3 Glossary: add `Kleidungsstück` (Piece) / `Look` (Outfit) terms with copy keys; re-term the wardrobe rows that still say "Kostüm" where the aggregate split (category + role rows stay).
- [x] 1.4 Re-term cross references in `docs/design/screens/{cast-view,scenes,script-view,seasons,seasons-home,navigation-shell,fundus,role-extract}.md`.

## 2. OpenSpec artifacts

- [x] 2.1 `proposal.md`, `design.md`, `tasks.md`, `.openspec.yaml` for this change.
- [x] 2.2 Delta specs: `flutter-wardrobe-pieces-outfits` (new capability) and `flutter-client-authz` (outfit command gating).
- [x] 2.3 `openspec validate 739-piece-and-outfit-frontend --strict` clean.

## 3. Data layer — photo bindings

- [x] 3.1 `PhotoRepository.upload` targets `/v1/pieces/{id}/photos` (raw Dio path, same error mapping); regression test asserts the recorded path.
- [x] 3.2 Outfit photo surface: `uploadOutfit`, `getOutfitBytes`, `deleteOutfitPhoto` through the generated client + `Result` discipline.
- [x] 3.3 Generalize the bounded watch to `watch<View>` with an injected terminal predicate; keep `isPhotoWatchTerminal` (piece) and add `isOutfitPhotoWatchTerminal`.
- [x] 3.4 Unit tests: piece/outfit upload routes, delete, bytes, watch terminal/expiry on a fake clock; Err branches asserted.

## 4. Presentation rename — costume → piece

- [x] 4.1 Move `lib/features/costumes/` → `lib/features/pieces/` and rename the files (`pieces_screen`, `piece_detail_screen`, `pieces_controller`, `pieces_state`, `piece_identity`, `widgets/pieces_widgets`).
- [x] 4.2 Rename the Dart identifiers per design D2 (`CostumeRow` → `PieceRow`, `CostumesScreenState` → `PiecesScreenState`, `costumeTileIdentity` → `pieceTileIdentity`, providers, …) — behaviour-neutral.
- [x] 4.3 Remove the retired assignment affordances (assign/reassign/unassign copy + command paths) from the piece detail.
- [x] 4.4 Rename ARB keys `costume*` → `piece*` (category keys exempt) and `sceneDetail*Costume*` → `sceneDetail*Outfit*`; `flutter gen-l10n` + de/en parity clean.
- [x] 4.5 Regenerate the affected goldens and rename the golden files (`pieces_screen_*`, `piece_detail_editor_open`).
- [x] 4.6 Re-term the `.pi/skills` copies (`flutter-testing-recipes`, `design-wireframe-salt`, `openspec-screen-prompt`) where they name the retired model.

## 5. Outfit feature

- [x] 5.1 `lib/features/outfits/outfits_controller.dart` (+ generated providers): list-by-character fetch/cache, create, create-variant, rename, notes, add/remove piece — each `// AUTHZ-GATE:`-commented and gated on the awaited membership predicate.
- [x] 5.2 `outfits_state.dart`: `AsyncValue` projection + version-fenced overlays (`shouldClearOutfitOverlay`) + command-error surface routing by problem `code`.
- [x] 5.3 `OutfitListSection` in `character_detail_screen.dart`: rows (name, variant marker, piece count), empty state, "Look erstellen".
- [x] 5.4 `OutfitDetailScreen`: rename, notes, ordered piece rows (add via the season/fundus piece picker, remove with version echo), variant lineage link, `Variante erstellen`, photos section on the outfit bindings.
- [x] 5.5 Piece ↔ outfit navigation (design D4): outfit piece row → piece detail of the outfit's season; graceful missing-row fallback.
- [x] 5.6 New copy keys (`outfit*`) in `app_de.arb` + `app_en.arb`, glossary rows, ICU plurals for the piece count.

## 6. Scene casting copy + Gherkin

- [x] 6.1 Scene detail: "Looks ({count})", "Look zuweisen", "Look wählen", "Kein Look in dieser Szene." on the existing outfit-beat machinery.
- [x] 6.2 Integration seed helper posts `/v1/pieces` + `/v1/outfits` (no `/v1/costumes`), continuity photo step uses the piece binding.
- [x] 6.3 Gherkin: outfit casting scenario (cast a look, reuse the `outfit_id` for continuity, fork a variant for the deviation) runs on device.

## 7. Tests and gates

- [x] 7.1 Unit: outfit state merge/version fence/Err branches; photo watch generalization; copy-key usage.
- [x] 7.2 Widget: outfit list section (rows, variant marker, empty, create disabled on blank name), outfit detail (rename, ordered pieces, add/remove, variant fork, photos), piece detail without assignment affordances, scene beat picker on outfits.
- [x] 7.3 Goldens: outfit list + outfit detail (light/dark × Android/macOS) using the German template locale.
- [x] 7.4 `dart format --set-exit-if-changed .`, `flutter analyze`, `flutter test --coverage` (≥ 80 %), `breakdown_lints_runner`, `flutter gen-l10n` parity, `scripts/check-design-diagrams.sh`.
- [x] 7.5 `scripts/regen-client.sh` byte-identical (no client drift; the contract is an input of this change).
- [x] 7.6 Version + changelog: `pubspec.yaml` `0.4.0-beta.14+106` → `0.4.0-beta.15+107` (ADR-033), `CHANGELOG.md` entry.
