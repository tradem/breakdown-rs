<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

# Scene detail — always-visible cast table + row context menu

## Why

Issue #902 is the presentation follow-up to #834's merged cast/look table. Four
findings on the scene detail screen (German UI):

1. **The cast was hidden by default.** `_SceneCastLooksSection` returned a
   `SectionCard` → `ExpansionTile` with `initiallyExpanded: false`, so a cold
   open showed one collapsed row of grey header text. A cast list is page
   *content* ("who is in this scene, in which look"), not a secondary detail
   that earns collapsing.
2. **Four icon buttons per row squeezed the one column that carries
   information.** The figure cell spent its width on `edit_outlined` +
   `person_remove_outlined`, the look cell on `delete_outline` (+ `add`), all at
   `size: 18` with `VisualDensity.compact` — roughly 32 dp boxes, i.e. **below
   the 48 dp minimum touch target** — and the 4/6 split then ellipsized the look
   label on a ~360 dp phone down to a few characters.
3. **Nothing separated the rows, and dark mode made it worse.** The header band
   was `labelSmall`/`onSurfaceVariant` on the *same* surface as the body, and a
   row had no band, no hairline, no alignment column — only vertical padding. In
   dark mode the M3 default `Card` colour (`surfaceContainerLow`) is nearly
   indistinguishable from `surface`, so the section read as loose floating text:
   no column axis, no row identity, no scan line.
4. **The actions were icon-only**, which the glossary's visible-label norm
   tolerates only for reinforcement. In a context menu the same four actions
   become **labelled** items — a net accessibility improvement.

## What changes (frontend only)

**1. The cast is always visible.** The section drops the `SectionCard` wrapper
for a plain section header (`Figuren 2 · Looks 3` keeps the counts) followed by
the table; there is no expand step. `SectionCard` stays the shared component for
the sections that legitimately collapse (the shooting days).

**2. Real table chrome, in both schemes, from theme roles only.**
Header band on `surfaceContainerHighest` with `onSurfaceVariant` text and the
same column flex as the body; zebra rows alternating `surface` /
`surfaceContainerLow` plus an `outlineVariant` hairline drawn as a
`DecoratedBox` border (never a `Divider` widget, so #834's no-divider assertion
stays honest); one shared inset so the look column starts at the same x as its
label; long look labels wrap to a second line instead of ellipsizing.
No hardcoded colour, no new DTCG token — `ColorScheme` roles only.

**3. All four actions move into a row context menu.** Tap (or long-press) the
row → `showModalBottomSheet` with labelled `ListTile`s: **Bearbeiten** →
Cast screen (disabled, never absent, when no `SeasonView` resolves),
**Look zuweisen / + Lookwechsel**, **Look entfernen** (only on a row that
carries a beat), **Figur entfernen** (only on the figure's first row). The row
becomes one button-like tap target (`Semantics(button: true, hint: …)`) with a
decorative `chevron_right` cue and a ≥ 48 dp height. Every removal keeps its
existing confirm dialog, every command path, version echo, AUTHZ-GATE and
error-copy mapping is untouched.

**4. Stable keys.** `scene-cast-<sceneId>`, `scene-cast-empty`,
`scene-character-<characterId>`, `scene-piece-beat-<ch>-<order>`,
`scene-piece-empty-<ch>`, `scene-piece-arrow-<ch>-<order>`,
`scene-character-assign-<sceneId>`, `scene-pieces-overlay-status` and both
confirm-dialog keys are unchanged. New: `scene-cast-row-<ch>-<order>`
(`-none` for the no-look row, the tap target), `scene-cast-table`,
`scene-cast-title`, `scene-cast-header-band`, `scene-cast-menu-<ch>-<order>`,
`scene-cast-menu-edit-<ch>`, `scene-cast-menu-add-look-<ch>`,
`scene-cast-menu-remove-look-<ch>-<order>`,
`scene-cast-menu-remove-character-<ch>`. Retired: the four inline-button keys
(`scene-character-edit-*`, `scene-character-remove-*`, `scene-piece-remove-*`,
`scene-piece-add-change-*`, `scene-piece-assign-*`) — every test and the one
Gherkin step now open the row menu first.

**Copy keys.** New `sceneDetailCastMenuTitle` (`Aktionen für {name}`) and
`sceneDetailCastMenuHint` (the row's semantics hint) in both ARB files;
`sceneDetailRemoveCharacterTooltip` changed from the ambiguous `Entfernen` to
`Figur entfernen` because it is now a visible MENU LABEL, not an icon tooltip.
`sceneDetailAddLook` was considered and dropped: `sceneDetailAssignOutfit`
("Look zuweisen") and `sceneDetailAddChange` ("+ Lookwechsel") already read as
menu labels.

## Reconciling with the #834 "no divider chrome" rule

#834 rejected the `ExpansionTile`'s own top/bottom **section** chrome; that rule
still holds (no card outline, no `Divider`, no tile borders). The cast table has
its own **table** chrome: a header band, zebra bands and a hairline border. The
distinction is now written down in `docs/design/screens/scenes.md`, and the
widget test keeps asserting `find.byType(Divider) == findsNothing` while the
border decoration is asserted separately.

## Non-goals

- No backend, contract or `backend/openapi.yaml` change; no
  `vendor/breakdown_api/` regeneration.
- No change to which commands are dispatched, their version echo, their
  AUTHZ-GATE or their error copy.
- Not the shooting-days section, not the synopsis, not the scene list, not the
  Cast view (`role_extract_screen.dart`).
- No new design tokens; `ColorScheme` roles only.
- No new Riverpod provider: the menu is local widget state, the commands keep
  their controllers.

## Impact

Frontend only: `lib/features/scenes/scene_detail_screen.dart` (cast section,
label band, row, row menu), `lib/design/components/section_card.dart` (one
doc-comment sentence naming the non-collapsing exception), de/en ARB keys +
regenerated `lib/l10n/generated/`, the widget tests + both goldens (light and
dark), `integration_test/gherkin/steps/outfit_casting_steps.dart`, and
`docs/design/screens/scenes.md` + `docs/design/glossary.md`.

## Related

- #834 — merged the two lists into one cast section (the collapse-by-default and
  the icon row are what this change revisits).
- #546 / #550 — the scene costume-assignment surface and beat de-duplication the
  table renders.
- #669 — cast row/beat keys the widget tests and Gherkin steps rely on.
- #611 — the Cast screen the `Bearbeiten` item still opens.
- #549 — the visible-label norm the menu items now satisfy better than the icon
  row did.
