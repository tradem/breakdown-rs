<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: space-bunny (opencode-go) -->

## MODIFIED Requirements

### Requirement: Hierarchy Navigation Spine
Season rows on the seasons overview SHALL navigate to `BlocksScreen`
(via `Navigator.push`, no new routing package), block rows to
`EpisodesScreen`, episode rows to `ScenesScreen`. The spine SHALL be
entered from the production overview screen, which is pushed from the
season scope picker's production entry on the active destination's nested
navigator (it is no longer a shell destination). Each pushed screen SHALL
receive the parent read DTO as its navigation context; command payloads
SHALL source every id (`series_id`, `season_id`, `block_id`, `episode_id`)
exclusively from that DTO — never from an additional projection lookup.
Back/Up SHALL return to the parent list on both platforms.

#### Scenario: Navigating to a season's blocks
- **WHEN** an authenticated user opens the production overview for a
  season and taps a projected block row.
- **THEN** `BlocksScreen` pushes with that season's context and renders
  the season's `BlockView` rows (`GET /v1/blocks?season_id=…`).

#### Scenario: Navigating to a block's episodes
- **WHEN** the user taps a block row.
- **THEN** `EpisodesScreen` pushes with the `BlockView` as context and
  renders the block's `EpisodeView` rows via the server-side filter
  (`GET /v1/episodes?block_id=…`, backend issue #335); error copy is
  keyed on the stable problem `code` from the per-operation RFC 9457
  responses (backend issue #343).

#### Scenario: Back navigation
- **WHEN** the user invokes system back (Android) or mouse-back (macOS)
  on `EpisodesScreen`.
- **THEN** the navigator pops to `BlocksScreen` showing the same season
  context; no re-fetch storm is triggered by the pop itself.

## ADDED Requirements

### Requirement: Season-Wide Chronological Script Overview
The shell's Script destination SHALL render the active season's scenes as
one continuously numbered chronological overview ordered by `scene_number`.
Because the scene read model is episode-scoped (`GET /v1/scenes` requires
`episode_id`), the overview SHALL be composed client-side from the season's
blocks, their episodes and their scenes. The composition SHALL be
read-only, SHALL reuse the existing authenticated read seams and Drift
caches, and SHALL surface a partial-load notice — never a silently
shortened script — when one episode's scenes fail to load. Tapping a row
SHALL push the scene detail screen with that scene read DTO as navigation
context.

#### Scenario: Scenes from all episodes appear in one numbered list
- **WHEN** the active season has two episodes whose scenes are numbered
  1–12 and 13–27 respectively.
- **THEN** the Script destination lists all scenes once, ordered by scene
  number, and each row carries its scene number as a visible label.

#### Scenario: A failing episode degrades visibly
- **WHEN** scenes of one episode fail to load while other episodes succeed.
- **THEN** the loaded scenes render with a partial-load notice naming the
  incomplete state; the list is never presented as the season's complete
  script.

#### Scenario: A failing block degrades visibly at ITS level
- **WHEN** the episode list of one block fails to load (its scenes are
  unknown, not empty) while other blocks succeed.
- **THEN** a partial-load notice names the failed BLOCKS (never counts them
  as episodes), and the scenes that are present still render.

#### Scenario: Row tap carries the scene DTO
- **WHEN** the user taps a scene row.
- **THEN** the scene detail screen pushes with that scene's read DTO as
  navigation context and issues no additional projection lookup to fill in
  ids.
