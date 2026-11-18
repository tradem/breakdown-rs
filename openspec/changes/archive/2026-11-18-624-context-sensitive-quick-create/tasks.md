<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (neuralwatt) -->

# 624-context-sensitive-quick-create — implementation tasks

## 1. Active-episode scope (auth layer)

- [x] 1.1 Create `lib/auth/active_episode.dart`: `ActiveEpisodeScope`
  (`seasonId`, `blockId`, `episodeId`, `episodeNumber`, `episodeName`) +
  `@Riverpod(keepAlive: true) ActiveEpisode` notifier with `set`/`clear`,
  mirroring `ActiveBlock` (synchronous state, fire-and-forget persistence)
- [x] 1.2 Create `lib/auth/active_episode_store.dart`: per-season secure
  document `Map<seasonId, {blockId, episodeId, number, name}>` with the same
  mutex/self-heal/`Result` discipline as `ActiveBlockStore`, plus
  `activeEpisodeStoreProvider` / `activeEpisodePersistedProvider`
- [x] 1.3 Run `build_runner` to emit `active_episode.g.dart`
- [x] 1.4 Unit tests: store round-trip, corrupt-payload self-heal, unknown
  value shapes dropped, provider set/clear; both `Ok` and `Err` branches

## 2. Scope set sites

- [x] 2.1 Set the scope in `EpisodesScreen` (row → `ScenesScreen`; episode
  shooting-days icon → `ShootingDaysScreen`) before the push
- [x] 2.2 Set the scope in `ScriptTabScreen` (scene row → `SceneDetailScreen`)
  and `ScheduleTabScreen` (day row → `ShootingDaysScreen`) before the push
- [x] 2.3 Wire teardown in `sign_out.dart`: clear the store on backend switch,
  invalidate `activeEpisodeProvider` / `activeEpisodePersistedProvider` at the
  same seams the block scope uses
- [x] 2.4 Widget tests: each entry point sets the scope before navigation

## 3. Episode chip + picker

- [x] 3.1 Create `lib/features/shell/active_episode_chip.dart`: labelled chip
  (`Episode {n}` / name, glossary icon, tooltip), hidden when unset,
  foreign-season narrative
- [x] 3.2 Episode picker screen resolving the scope block's episodes via
  `episodesListFetchProvider(blockId, seasonId)`; pick sets the scope and pops
  (reuse the block picker's loading/error scaffolds)
- [x] 3.3 Render the chip in `ShellContextBar` next to the block chip
- [x] 3.4 Widget tests: hidden/shown arms, label, picker pick-and-pop,
  foreign-season narrative; golden of the context bar with the chip

## 4. Quick-create entries

- [x] 4.1 Extend `shellQuickCreateActions(l10n, {ActiveEpisodeScope? episode})`
  additively: context-free list unchanged when `episode == null`; prepend
  "Neue Szene" / "Neuer Drehtag" entries otherwise (glossary icons, visible
  labels + subtitles, test keys)
- [x] 4.2 Pass the scope from `AppShellState` when opening the sheet
- [x] 4.3 Widget tests: both scope states (entry count, labels, routed page
  types, context-free entries still present)

## 5. Full-screen create pages + shared forms

- [x] 5.1 Extract `CreateSceneForm(episodeId)` (public) from
  `create_scene_sheet.dart`; the sheet reuses it
- [x] 5.2 Extract `CreateShootingDayForm(episodeId)` (public) from
  `_CreateShootingDaySheet`; the sheet reuses it
- [x] 5.3 Change `ScenesController.create` to take `episodeId` (the only
  field it read from `EpisodeView`)
- [x] 5.4 Create `CreateSceneScreen({required String episodeId})` and
  `CreateShootingDayScreen({required String episodeId})`: Scaffold + AppBar +
  shared form + command-error banner keyed on the episode
- [x] 5.5 Widget tests: both pages submit through the episode-keyed
  controller, pop on success, surface a failed command (Err branch); the
  AUTHZ gate denies with no request on an unresolved session

## 6. Localization & glossary

- [x] 6.1 Add de/en keys (`quickCreateSceneTitle`/subtitle,
  `quickCreateShootingDayTitle`/subtitle, `episodeChip*`, picker copy);
  regenerate `flutter gen-l10n`; parity holds
- [x] 6.2 Add glossary rows for the two quick-create entries and the episode
  chip; update `docs/design/screens/navigation-shell.md` component table

## 7. Verification

- [x] 7.1 `dart format --set-exit-if-changed .`, `flutter analyze`,
  `flutter test` clean
- [x] 7.2 Regenerate goldens touched by the context bar and add goldens for
  the two create pages
- [x] 7.3 `openspec validate 624-context-sensitive-quick-create --strict`
  passes
