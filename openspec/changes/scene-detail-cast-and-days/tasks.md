<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3 (neuralwatt) -->

# Tasks — scene detail: plan before cast, one cast table, mixed-mood icons

## 1. Order and day affordances (`lib/features/scenes/scene_detail_screen.dart`)

- [x] 1.1 `_SceneDetailBody` owns the body: header → synopsis → **shooting days**
      → cast. It resolves the day candidates once (`_realDayCandidates`) and feeds
      the section AND the header chip, so the affordances cannot disagree.
- [x] 1.2 Day rows carry icons: day board, **move to another day**
      (`scene-shooting-day-move-<day>`), unschedule. The schedule action keeps its
      label with an icon.
- [x] 1.3 `_pickDayAndSchedule(.., replaceDayId)` — schedule first, release the
      current day only after that ACK (chained on the ACK version); a refused
      schedule dispatches nothing further, a refused release leaves both rows.
- [x] 1.4 The script-day chip carries the binding icon
      (`scene-script-day-assign-<scene>`), disabled exactly when no candidate day
      exists. It schedules without releasing (a bind is not a move).
- [x] 1.5 Tests: days above cast, chip binding + picker, disabled chip with no
      candidate, move ordering (schedule then unschedule), refused move keeps the
      day.

## 2. One cast table

- [x] 2.1 `_SceneCastLooksSection` replaces `_SceneCharactersSection` +
      `_SceneOutfitsSection`; header `sceneDetailCastTitle(characters, looks)`,
      card key `scene-cast-<scene>`.
- [x] 2.2 `_CastTableHeader` (column labels) + `_CastRow` (figure cell, look cell
      with category icon / arrow / cue, actions). Existing per-row keys are kept
      (`scene-character-<id>`, `scene-piece-beat-<char>-<order>`,
      `scene-piece-remove-*`, `scene-piece-add-change-<char>`,
      `scene-character-remove-<id>`) and the no-look placeholder keeps
      `scene-piece-empty-<char>`.
- [x] 2.3 Edit route: `scene-character-edit-<id>` pushes `RoleExtractScreen`
      (Cast screen → character detail) with the season row from the new
      `seasonById` provider (cache-first, fetch on miss); returning refreshes the
      scene.
- [x] 2.4 Bottom action „Figur und Look zuweisen"
      (`scene-character-assign-<scene>`) = assign + look picker; a cancelled
      picker keeps the figure cast; a figure without looks gets the explicit hint
      (`sceneDetailNoLooksForFigure`) instead of an empty sheet.
- [x] 2.5 l10n (de + en): `sceneDetailCastTitle`, `sceneDetailCastColumnCharacter`,
      `sceneDetailCastColumnLook`, `sceneDetailAssignCharacterAndLook`,
      `sceneDetailEditCharacterTooltip`, `sceneDetailNoLooksForFigure`,
      `sceneDetailMoveToOtherDay`, `sceneDetailAssignScriptDayTooltip`; the two
      now-unused section titles (`sceneDetailCharactersTitle`,
      `sceneDetailOutfitsTitle`) are removed.
- [x] 2.6 Tests: one row carries figure + look (with the column labels), the edit
      route opens the character detail, the combined assign flow casts then opens
      the look picker; the existing characters/looks tests follow the merged card
      (scroll + count copy).

## 3. Mixed-mood icons (`lib/design/`)

- [x] 3.1 `BreakdownMaterialIcons.forSceneMood` returns
      `({List<IconData> locations, IconData time})?`: one location icon per named
      component, the distinct `I`+`A` pair (either order) collapsed to the
      threshold icon, `null` for anything unparsable.
- [x] 3.2 `SceneMoodLabel` renders `locations` + `time` (still decorative, still
      next to the visible label).
- [x] 3.3 `canonicalSceneMoods` additionally offers the `A/I/*` forms.
- [x] 3.4 Tests: `A/I/T` resolves to the threshold + day icon (resolver AND
      widget), repeated locations keep one icon each, the non-shorthand cases stay
      `null`, and the scene header renders the mixed-mood icons.

## 4. Docs, golden, gates

- [x] 4.1 `docs/design/screens/scenes.md`: layout (days first, one cast table),
      the component table rows for the new affordances, the interactions
      (assign-then-look, move ordering, edit route), the `A/I/*` chips.
- [x] 4.2 Scene-detail golden rebaselined (one affected file).
- [x] 4.3 `flutter analyze` clean, `flutter test` green, l10n key parity (de/en),
      `frontend-flutter/CHANGELOG.md` + version bump.
