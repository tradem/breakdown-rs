<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3 (neuralwatt) -->

# Proposal: Script overview — "Scenes from the script", enriched scene rows, active-episode scope filtering (issue #709)

## Why

The Script tab (destination 2, #610) shows only scene number, summary and
episode. The issue asks for (1) a proper view title "Szenen aus dem Skript",
(2) an enriched scene row (episode before scene number, summary with
ellipsis, metadata line), (3) filtering by the sticky active-episode scope
(#624), and (4) the episode pill showing the number before the title.

## Decisions (confirmed with the user)

| Decision point | Choice |
|---|---|
| Title wiring | Separate view-bar title (`viewTitleScript`); the `navScript` destination label stays short so the bottom bar does not grow |
| Shooting-day metadata | `scriptDay` (fictional script chronology, rendered via the existing `sceneDay` key "Tag: {day}"); absent → omitted |
| Costume count | Distinct `costumeId`s across `costumeBeats` (the same costume worn twice counts once) |
| Episode picker rows | Same "<Number> · <Name>" format as the pill |

## What Changes

1. **View title:** `ShellDestinations.viewTitle` returns `viewTitleScript`
   for the Script destination; l10n key `viewTitleScript`
   ("Szenen aus dem Skript" / "Scenes from the script").
2. **Scene row** (`_ScriptRowTile`): title = summary, `maxLines: 1`,
   ellipsis (fallback `scriptSceneNumber`/`scriptSceneNumberUnknown` as
   today); subtitle = identity + metadata joined by " · ", absent parts
   omitted, in this order:
   - episode before scene number: "{episode}, Szene {number}"
     (`scriptRowEpisodeScene`; episode part = name or "Episode {n}"),
     episode alone for an unnumbered scene;
   - shooting day (`sceneDay` reuse);
   - location;
   - "{count} Figur(en)" (`scriptRowCharacters`, `assignedCharacters.length`);
   - "{count} Kostüm(e)" (`scriptRowCostumes`, distinct `costumeId`s).
   Widget keys (`script-scene-<id>`) and the detail push (#624 sticky
   scope) stay unchanged.
3. **Episode scope filtering** (`seasonScriptFetchProvider`): the sticky
   episode scope (same season) wins over the block scope — the composition
   narrows to the scope's block and skips scene fetches for other episodes.
   Foreign-season scope ignored (chip rule). Pure helper
   `effectiveEpisodeFilter` + provider tests.
4. **Episode pill** (`ActiveEpisodeChip`) and picker rows: named episodes
   render "{number} · {name}" (`episodeNumberName` l10n key); nameless keep
   "Episode {n}". The picker's now-redundant number subtitle is dropped.

## Impact

- **Code:** `lib/features/shell/app_shell.dart`,
  `lib/features/shell/script_tab_screen.dart`,
  `lib/features/scenes/season_script_controller.dart`,
  `lib/features/shell/active_episode_chip.dart`, l10n ARBs (+gen).
- **Tests:** app_shell title assertion, chip label tests + goldens,
  three_views script-row tests, new controller scope tests.
- **No backend/OpenAPI change** — filtering is client-side on already
  composed parts (CQRS boundary unchanged, no new reads).
