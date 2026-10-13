<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (neuralwatt) -->

## Why

The shell quick-create sheet (issue #612, PR #623) shipped a deliberately
context-free list: KI-Import and the season setup wizard. That was the right
v1 — the sheet is the one-plus-action aggregation surface, but the create
commands a user most often wants *while working inside an episode* (a new
scene, a new shooting day) still live behind per-screen FABs.

Issue #624 asks for the context-sensitive half of the sheet: when an episode
scope is resolvable, offer "Neue Szene" and "Neuer Drehtag" alongside the
context-free entries; when nothing is in context, keep the list exactly as
it is. The enabler is an **active-episode scope** — the shell already tracks
a sticky block scope (issue #378/#382) but has no episode equivalent, so
there is nothing to resolve the two commands' `episode_id` from.

The two create flows are today modal bottom sheets (a centered dialog on
macOS). The PO decision for this change is to reach them from the
quick-create sheet as **full-screen pages** — consistent with the other
sheet entries (AI import, wizard), which already push full-screen routes,
and avoiding the modal-dialog presentation the PO rejected.

## What Changes

- **New sticky active-episode scope** (`ActiveEpisode`): the episode-level
  sibling of the active-block scope, set implicitly when the user enters an
  episode's context (episode row → scenes, the episode shooting-days entry,
  a Script scene row, a Schedule day row) and changeable via a new top-bar
  **episode chip** with its own picker. Persisted per season like the block
  scope and cleared on sign-out / backend switch.
- **Context-sensitive quick-create entries**: `shellQuickCreateActions`
  gains an optional episode scope; with a scope present it prepends
  "Neue Szene" and "Neuer Drehtag" entries that push full-screen create
  pages for that episode. With no scope the list is unchanged (the
  data-driven contract stays additive).
- **Full-screen create pages** for scene and shooting day
  (`CreateSceneScreen` / `CreateShootingDayScreen`) hosting the existing
  form fields; the in-context FAB sheets keep their current presentation
  and share the same form widgets.
- **AUTHZ-GATE mirror**: the new entries keep the create flows' existing
  auth-only client gate (authenticated session required before any network
  call; a pending restore disables, never denies).
- **l10n (de/en) and glossary rows** for the two new entries and the
  episode chip.

## Capabilities

### New Capabilities

- `flutter-quick-create`: the shell quick-create sheet's context-sensitive
  entry set — the active-episode scope that feeds it, the full-screen create
  pages it pushes, and the episode chip that surfaces/changes the scope.

### Modified Capabilities

- None. The episode-entry set sites extend the hierarchy navigation spine's
  behavior, but the scope itself is specified (with those sites) under the
  new `flutter-quick-create` capability, so no existing spec-level behavior
  changes.

## Impact

- **Code (frontend only):** new `lib/auth/active_episode.dart` +
  `active_episode_store.dart` (scope + persistence), new
  `lib/features/shell/active_episode_chip.dart`, changes to
  `lib/features/shell/app_shell.dart` (context bar + quick-create scope),
  `quick_create_sheet.dart` (additive entries), new full-screen create pages
  under `lib/features/scenes/` and `lib/features/shooting_days/`, shared
  form extraction, episode-scope set sites in `episodes_screen.dart` /
  `script_tab_screen.dart` / `schedule_tab_screen.dart`, and
  `lib/features/auth/sign_out.dart` (scope teardown).
- **No backend/API changes** (`backend/openapi.yaml` untouched → no Dart
  client regeneration, no drift-check run).
- **Docs:** `docs/design/glossary.md` rows for the new entries and the
  episode chip; `docs/design/screens/navigation-shell.md` component table.
- **Testing:** unit tests for the episode store/provider, widget tests for
  the chip, both quick-create scope states and the two create pages,
  goldens for the new pages and the context bar with the chip.
