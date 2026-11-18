<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

# Tasks — scene detail: always-visible cast table + row context menu

## 1. The cast section stops collapsing (`lib/features/scenes/scene_detail_screen.dart`)

- [x] 1.1 `_SceneCastLooksSection` returns a plain `Column` keyed
      `scene-cast-<sceneId>`: section header (`scene-cast-title`, counts kept),
      then the table card (`scene-cast-table`). No `SectionCard`, no expand step.
- [x] 1.2 The empty state (`scene-cast-empty`), the assign button
      (`scene-character-assign-<sceneId>`) and the overlay status row
      (`scene-pieces-overlay-status`) keep their keys; the status row now renders
      BELOW the table with a `space4` separation.
- [x] 1.3 `lib/design/components/section_card.dart`: one doc-comment sentence
      naming the cast table as the deliberate non-collapsing exception.

## 2. Table chrome from `ColorScheme` roles only

- [x] 2.1 `_CastTableHeader` → band container (`scene-cast-header-band`) on
      `surfaceContainerHighest`, `onSurfaceVariant` labels, the body's 4/6 flex
      and a trailing spacer of the row's chevron width, so the labels sit exactly
      over their columns at every width.
- [x] 2.2 `_CastRow` → `Semantics(button, hint)` + `Material` band
      (`surface` / `surfaceContainerLow`) + `InkWell` (row key
      `scene-cast-row-<ch>-<order>`, `-none` for the no-look row) +
      `DecoratedBox` hairline in `outlineVariant`. Never a `Divider` widget.
- [x] 2.3 Rows are ≥ 48 dp (`_castRowMinHeight`) and one tap target; the look
      label wraps (`maxLines: 2`) instead of stubbing; the trailing
      `chevron_right` (`_castActionColumnWidth`) is the affordance cue.
- [x] 2.4 No `Color(...)` literal and no new DTCG token; `design/tokens/`
      untouched.

## 3. The four actions become a labelled row menu

- [x] 3.1 `_CastRowMenu` (`showModalBottomSheet` + `ListTile`s) with the title
      `sceneDetailCastMenuTitle(name)`; items `scene-cast-menu-edit-<ch>`,
      `scene-cast-menu-add-look-<ch>`,
      `scene-cast-menu-remove-look-<ch>-<order>`,
      `scene-cast-menu-remove-character-<ch>`.
- [x] 3.2 Per-row availability: Bearbeiten and Figur entfernen only on the
      figure's first row (Bearbeiten DISABLED, never absent, without a
      `SeasonView`), Look entfernen only where the row carries a beat (its own),
      the add-look item on every row of the figure.
- [x] 3.3 The chip (`onTap`) and long-press open the same menu; the sheet closes
      before the action's dialog/picker opens.
- [x] 3.4 Command paths untouched: the existing confirm dialogs, optimistic
      overlay, bounded-retry reconciliation, version echo, AUTHZ-GATE and
      `sceneBeatError*` / `characterErrorCopy` mapping.

## 4. Copy keys (de template + en parity)

- [x] 4.1 New `sceneDetailCastMenuTitle`, `sceneDetailCastMenuHint` in both ARB
      files; `sceneDetailRemoveCharacterTooltip` now reads `Figur entfernen` /
      `Remove character` (a visible menu label, not an icon tooltip).
- [x] 4.2 `flutter gen-l10n` + the de/en key-parity check green; the regenerated
      `lib/l10n/generated/` is committed.

## 5. Tests

- [x] 5.1 Widget (Tier 2) — `test/features/scenes/scene_detail_screen_test.dart`:
      the cast renders without an expand step; the label band and its column keys;
      banding/hairline asserted in BOTH brightnesses with the scheme roles; no
      `Divider`; tap and long-press open the same labelled menu; per-row item
      availability; Bearbeiten disabled without a season row; each item runs its
      existing confirm/picker path; the reconciling AND the stale/cloud-off rows
      render below the table; the row is one ≥ 48 dp tap target with a semantics
      hint and a chevron; the old inline-button keys are gone.
- [x] 5.2 Golden (Tier 2) — re-baselined `goldens/scene_detail_screen.png` plus a
      new `goldens/scene_detail_screen_dark.png` of the same German-locale screen.
- [x] 5.3 Gherkin (Tier 3) — `integration_test/gherkin/steps/outfit_casting_steps.dart`
      casts through the row menu; no new `.feature` file.
- [x] 5.4 `flutter analyze`, `dart format --set-exit-if-changed .`,
      `breakdown_lints`, the ARB parity gate and `flutter test` green.

## 6. Documentation

- [x] 6.1 `docs/design/screens/scenes.md`: the wireframe loses the `{^ …}` cast
      section, the *Components & Semantics* table gains the label band, the row
      band and the row menu, and the #834 no-divider note is narrowed to section
      chrome (with the table chrome spelled out).
- [x] 6.2 `docs/design/glossary.md`: the four actions are menu-item rows
      (`edit_outlined`, `add`, `delete_outline`, `person_remove_outlined`) plus
      the `chevron_right` cue.
- [x] 6.3 `scripts/check-design-diagrams.sh` green (the PlantUML block compiles).
