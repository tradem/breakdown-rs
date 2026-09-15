<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3 (neuralwatt) -->

## MODIFIED Requirements

### Requirement: Hierarchy Navigation Spine
Season rows SHALL navigate to `BlocksScreen` (via `Navigator.push`, no
new routing package), block rows to `EpisodesScreen`, episode rows to
`ScenesScreen`. These hierarchy pushes SHALL occur within the Planen
tab of the navigation shell, operating on that tab's nested
navigator. Each pushed screen SHALL receive the parent read DTO as
its navigation context; command payloads SHALL source every id
(`series_id`, `season_id`, `block_id`, `episode_id`) exclusively from
that DTO — never from an additional projection lookup. Back/Up SHALL
return to the parent list on both platforms, and system back at the
Planen tab root stays on the tab (per the shell's back behavior).

#### Scenario: Navigating to a season's blocks
- **WHEN** an authenticated user taps a projected season row.
- **THEN** `BlocksScreen` pushes with that `SeasonView` as context and
  renders the season's `BlockView` rows (`GET /v1/blocks?season_id=…`).

#### Scenario: Navigating to a block's episodes
- **WHEN** the user taps a block row.
- **THEN** `EpisodesScreen` pushes with the `BlockView` as context and
  renders the block's `EpisodeView` rows via the server-side filter
  (`GET /v1/episodes?block_id=…`, backend issue #335); error copy is
  keyed on the problem `code`.

#### Scenario: Back at hierarchy root inside the shell
- **WHEN** the user is on the Planen tab root and presses system back.
- **THEN** the shell stays on the Planen tab (no lazy tab-switch
  chain); consecutive back at the initial tab root requests app exit
  per platform convention.

#### Scenario: Empty state
- **WHEN** a screen's merged row list is empty and no fetch is
  failing.
- **THEN** a plain-language empty state renders with the create call
  to action when the session gate allows it.

#### Scenario: 404 while viewing a deleted parent's children
- **WHEN** a pushed list screen's fetch returns a `*.not-found`
  problem.
- **THEN** the screen renders a 404 narrative and a back affordance;
  it does not render fabricated or stale rows as if current.
