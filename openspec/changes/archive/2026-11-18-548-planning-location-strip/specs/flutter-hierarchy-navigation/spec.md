<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3 (neuralwatt) -->

# flutter-hierarchy-navigation Delta

## MODIFIED Requirements

### Requirement: Hierarchy Navigation Spine

Season rows SHALL navigate to `BlocksScreen` (via `Navigator.push`, no new
routing package), block rows to `EpisodesScreen`, episode rows to
`ScenesScreen`. Each pushed screen SHALL receive the **full ancestor chain
as an immutable `PlanningLocation`** in `RouteSettings.arguments` — a typed
sealed ladder (`season → block → episode → scene`) in which each step
requires the previous one, so a non-contiguous chain (e.g. an episode
without its block) is not representable. Command payloads SHALL source
every id (`series_id`, `season_id`, `block_id`, `episode_id`) exclusively
from the read DTOs held by that location — never from an additional
projection lookup. Back/Up SHALL return to the parent list on both
platforms.

The shell SHALL render a visible **context strip** above the tab content in
all window-size morphologies, derived from the topmost route's location of
the active tab's navigator (pop and tab switches update it without extra
state), showing every level as icon AND visible text; when the width is
insufficient it collapses to the last segments while its merged semantics
node always announces the full path. Season-direct screens (costumes,
characters, costume categories, character detail) take the **season level
only** — they are not part of the block/episode chain and SHALL NOT pretend
to be. The shell SHALL also render a separate **scope chip** whenever an
active-block scope is set, showing the scoped block's label (degrading to
an explicit "unknown" narrative when the label cannot be resolved — never a
silent filter), indicating when the scope's season differs from the
navigated season, and opening the block picker on tap so the scope is
changeable.

#### Scenario: Navigating to a season's blocks
- **WHEN** an authenticated user taps a projected season row.
- **THEN** `BlocksScreen` pushes with that `SeasonView` as context and a
  `PlanningLocation.season` argument, and renders the season's `BlockView`
  rows (`GET /v1/blocks?season_id=…`); the strip shows the season.

#### Scenario: Navigating to a block's episodes
- **WHEN** the user taps a block row.
- **THEN** `EpisodesScreen` pushes with the `BlockView` as context and a
  `PlanningLocation.block` argument (season included) and renders the
  block's `EpisodeView` rows via the server-side filter
  (`GET /v1/episodes?block_id=…`, backend issue #335); error copy is
  keyed on the stable problem `code` from the per-operation RFC 9457
  responses (backend issue #343); the strip shows season and block.

#### Scenario: Navigating to an episode's scenes
- **WHEN** the user taps an episode row.
- **THEN** `ScenesScreen` pushes with a `PlanningLocation.episode`
  argument carrying season, block and episode DTOs; the strip shows all
  three — the season title is visible at every deeper level.

#### Scenario: Back navigation
- **WHEN** the user invokes system back (Android) or mouse-back (macOS)
  on `EpisodesScreen`.
- **THEN** the navigator pops to `BlocksScreen` showing the same season
  context; no re-fetch storm is triggered by the pop itself; the context
  strip updates to the season level **in the same frame** (the location is
  carried by the route, so no stale level can survive the pop).

#### Scenario: Invisible scope made visible
- **WHEN** an active-block scope is set (picked, restored from persistence,
  or single-block resolved) and the user navigates.
- **THEN** the scope chip is visible with the scoped block's label, so a
  silently filtered list is explainable; when the scope's season differs
  from the navigated season the chip says so instead of presenting the
  foreign block as if it applied; tapping the chip opens the block picker.

#### Scenario: Season-direct screens take the season level only
- **WHEN** the user enters `CostumesScreen`, `CharactersScreen`,
  `CharacterDetailScreen` or `CostumeCategoriesScreen` from season level.
- **THEN** the pushed route carries a `PlanningLocation.season` argument
  and the strip shows the season only — never a fabricated block/episode
  context.
