<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024 Breakdown RS Contributors -->
<!-- Co-authored-by: space-bunny-free (opencode-go) -->

## ADDED Requirements

### Requirement: Labelled Reports Entry On The Shooting-Days Screen

The shooting-days screen (`ShootingDaysScreen`) SHALL carry a reports entry
as a **labelled** control — visible label `Berichte` with an icon
reinforcing only, per the glossary's visible-label norm — that pushes the
episode's report index. The entry SHALL follow the adaptive pattern #549
established for the day board's reports entry: a `TextButton.icon` that
collapses into a **labelled** overflow-menu item at narrow widths, never
into a bare icon, with the width decision taken from a
`LayoutBuilder` breakpoint rather than a platform check. The Gherkin
contract key `reportsIndexOpen` SHALL sit on the tap target in **both**
branches, so the contract step resolves at either width.

The shooting-day tiles SHALL keep their existing action set: the index is
the single new affordance, and no tap target is added to a row that
already carries rename, reschedule, unschedule, archive and move actions.

The design decision D8 — reports are day-scoped and anchored in the day
board — is widened by this entry to: reports are day-scoped, anchored in
the day board, and **indexed per episode**. The per-day report surface
itself is unchanged.

#### Scenario: The entry is labelled and pushes the index

- **WHEN** the shooting-days screen renders at a width that fits the label
- **THEN** a control with the visible label `Berichte` and the key
  `reportsIndexOpen` renders, and tapping it pushes the report index for
  that episode

#### Scenario: The entry stays labelled at narrow widths

- **WHEN** the same screen renders at a width too narrow for the label
- **THEN** the entry collapses into an overflow-menu item that is labelled
  `Berichte` and still carries the key `reportsIndexOpen` on its tap target
  — it never degrades to an unlabelled icon

#### Scenario: Day rows do not gain a tap target

- **WHEN** the shooting-days screen renders its day rows
- **THEN** each row offers only its existing rename, reschedule,
  unschedule, archive and move actions — no report navigation target is
  added to the row

### Requirement: Season Id In The Shooting-Days Navigation Context

`ShootingDaysScreen` SHALL receive the season id as a **required named
navigation-context parameter**, threaded down by `EpisodesScreen` from the
parent `BlockView.season_id` — the same field `ScenesScreen` already
receives on the adjacent push. The shooting-days screen SHALL NOT resolve
the season id through a second projection read (for example a
`GET /v1/blocks/{id}` or an episode-side season lookup) to fill in
navigation context, and SHALL NOT read the shell's active season, because
the spine supports browsing a season that is not the active one. Command
payloads pushed from the shooting-days screen SHALL continue to source
every id exclusively from the parent DTO the user is acting on.

#### Scenario: The season id comes from the parent DTO

- **WHEN** the user taps an episode's shooting-days entry
- **THEN** `ShootingDaysScreen` is pushed with that episode's `EpisodeView`
  and the parent `BlockView.season_id`, and no additional request is issued
  to resolve the season

#### Scenario: A browsed, non-active season keeps its own context

- **WHEN** the user browses a season that is not the shell's active season
  and opens an episode's shooting-days screen there
- **THEN** the screen's season context is the browsed season's id, not the
  active season's
