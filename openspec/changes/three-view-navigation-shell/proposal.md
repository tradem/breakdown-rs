<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: space-bunny (opencode-go) -->

# 610 — Three task-oriented navigation views (Cast, Script, Schedule/Dispo)

## Why

The shell's four destinations — **Season | Planen | Kleidung | Mehr** —
are organised by *data model*, not by *task*: to answer "which costumes
does this actor wear in scene 14, and when do we shoot it?" the user
bounces across three tabs. The season tab is an overview that does not
navigate at all, the costume tab is a two-entry launcher, and `Mehr`
mixes user settings with costume-domain vocabulary. Issue #610 restructures
the bottom navigation into three **task-oriented** views plus a
minimal profile affordance — **Cast** (role extracts per actor),
**Script** (the chronological scene overview) and **Schedule/Dispo**
(the shooting-day board) — with season scoping lifted into a sticky,
shell-owned scope surface.

## What Changes

- **BREAKING** (test/gherkin bindings): the shell's destination set goes
  from four to three. `kSeasonTabIndex`/`kPlanenTabIndex`/
  `kKleidungTabIndex`/`kMehrTabIndex` are replaced by `kCastTabIndex`,
  `kScriptTabIndex`, `kScheduleTabIndex`; the destination keys
  `shell-destination-0..3` become `shell-destination-0..2`. Every
  widget test, integration test and on-device Gherkin step that binds to
  a tab index or destination key moves in the same change.
- **View set and order** (issue #610's table, glossary icons):
  `face` / **Cast** (0) — `menu_book` / **Script** (1) —
  `calendar_month` / **Schedule/Dispo** (2). Visible labels in all three
  morphologies; semantics become "Tab N of 3".
- **Cast view integrates the costume surface** (decision A): the Cast
  root hosts a two-way switch between the season-scoped **Figuren**
  (characters) and **Kostüme** (costumes) surfaces, plus a
  **Kategorien** app-bar action opening the season-scoped costume-category
  vocabulary. Costume categories never move into the profile/settings
  area — hard acceptance criterion from issue #610, cross-confirmed by
  #613.
- **Season scoping lifted into the shell context bar** (decision B): the
  existing `ActiveScopeChip` (block scope, issue #548) is generalised into
  a season + block pair. Tapping the season chip opens a season picker
  whose entries are: *pick a season* (sets the active season from the
  acted-on DTO), *Saisonen verwalten* (pushes `SeasonsScreen`) and
  *Produktion verwalten* (pushes the production overview carrying the
  block/episode hierarchy spine, the AI-import entry and the active-jobs
  row). The dissolved Season and Planen tabs become reachable through this
  picker instead of occupying destinations.
- **Script view is a flat chronological scene list** (decision D): the
  active season's scenes, continuously numbered (`scene_number`), gathered
  by a bounded client-side fanout over the season's blocks → episodes →
  scenes (the API's scene read model is episode-scoped, `GET
  /v1/scenes?episode_id=`) and merged into one ordered list. Tapping a row
  pushes `SceneDetailScreen` with that scene DTO as context.
- **Schedule/Dispo view** hosts the season's shooting days (the existing
  day board, incl. its labelled reports entry, unchanged).
- **Minimal profile affordance** (decision C): every view root carries one
  app-bar action opening a menu with identity, *Über die App*, *Einstellungen*
  and *Abmelden*. This is the minimal home the dissolved `Mehr` tab needs;
  issue #613 owns the final top-bar design and OmniSearch and refines this
  placement on top.
- **Glossary** (`docs/design/glossary.md`): the four destination rows are
  replaced by the three new ones; the former `Mehr`/`Kleidung` rows are
  retired or re-pointed. UI copy comes from the glossary, so the l10n
  key set moves with it.

## Capabilities

### New Capabilities

- `flutter-navigation-shell`: the adaptive three-view navigation shell,
  its destination/key/semantics contract, the season+block scope surface
  in the context bar, the scope picker (season, season management,
  production management) and the per-view profile affordance.

### Modified Capabilities

- `flutter-hierarchy-navigation`: the Season→Block→Episode→Scene spine no
  longer runs inside a "Planen" tab; it is reached through the scope
  picker's production entry (pushed on the active view's nested
  navigator), and the Script view replaces the per-episode scene list with
  a season-wide chronological list.
- `flutter-seasons-home`: the seasons overview is no longer a shell
  destination; it is pushed from the season scope picker. Its card
  semantics, empty state and create FAB are unchanged.
- `flutter-costume-categories-screen`: the entry point moves from the
  dissolved `Mehr` tab to the Cast view's app-bar action; the vocabulary is
  forbidden from the profile/settings surface.

## Impact

- `frontend-flutter/lib/features/shell/`: `shell_controller.dart`
  (+`.g.dart` regeneration if annotations change), `app_shell.dart`,
  `more_tab_screen.dart` (deleted), `planning_tab_screen.dart` (re-homed as
  the production overview), `active_scope_chip.dart` (season sibling chip),
  plus new `cast_tab_screen.dart`, `script_tab_screen.dart`,
  `schedule_tab_screen.dart`, `season_scope_chip.dart`,
  `season_scope_picker_screen.dart`, `production_overview_screen.dart`
  and `profile_menu_button.dart`.
- `lib/features/scenes/`: a new season-wide chronological controller
  (fanout) next to the existing episode-scoped one; `scenes_screen.dart`
  stays for the drill-down entry.
- `lib/l10n/{app_de.arb,app_en.arb}`: destination labels, view titles,
  scope-picker and profile copy; `flutter gen-l10n` output regenerated.
- `lib/design/material_icons.dart`: the three new destination icon pairs.
- `docs/design/glossary.md` + a new `docs/design/screens/<…>.md` screen spec.
- Tests/gherkin bindings: `test/features/shell/app_shell_test.dart`,
  `test/unit/shell/shell_controller_test.dart`,
  `integration_test/tab_switch_smoke_test.dart`,
  `integration_test/settings_base_test.dart`,
  `integration_test/gherkin/steps/common_steps.dart`.
- No backend change: the Script fanout reuses existing `Authenticated`
  read routes. No OpenAPI regeneration (`backend/openapi.yaml` untouched).
