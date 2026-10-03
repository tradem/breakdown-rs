<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->

## MODIFIED Requirements

### Requirement: Scene is scoped to an Episode

A `Scene` SHALL reference exactly one `Episode` via an `episode_id: EpisodeId`
field in its created event, replacing the prior `project_id: ProjectId`. The
`ProjectId` reference SHALL be removed entirely from the Scene context. A
Scene SHALL additionally carry an optional `summary: Option<String>` within
`SceneDetails` for free-form scene description. `SceneDetails` SHALL
additionally carry an optional `script_day: Option<String>` representing the
fictional script-chronology day (e.g. "1. Spieltag"), which is distinct from
the calendar `ShootingDay.date` and is used as a free-form search index for
finding scenes by script-day later. `script_day` has no further domain
semantics.

#### Scenario: Creating a scene scoped to an episode

- **WHEN** a `CreateScene { id, episode_id, series_id, details, source }`
  command is dispatched to a new Scene stream where `details.summary` may be
  `Some(String)` or `None` and `details.script_day` may be `Some(String)` or
  `None` — the command carries no `assigned_characters` field (scene
  characters are assigned via the `AssignCharacter` command after creation;
  the pre-change scenario text listing it as a `CreateScene` field was wrong)
- **THEN** the aggregate SHALL emit
  `SceneCreated { id, episode_id, details, assigned_characters, source,
  version }` where `details` carries `summary` and `script_day`,
  `assigned_characters` replays the characters carried by historic
  creation-time events, and the event SHALL NOT carry any `project_id` field
<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->

## MODIFIED Requirements

### Requirement: Scene read model reflects episode scoping

The scene projection SHALL store `episode_id` and SHALL expose queries for
Scenes by `episode_id`. Existing queries by `project_id` SHALL be removed. The
scene projection SHALL additionally store `script_day` and SHALL expose
queries for Scenes by `script_day` (exact or case-insensitive like match).
The scene read model SHALL additionally expose the scene's ordered costume
beats (`costume_beats`, see `scene-costume-assignment`) resolved per
(character, order) with character and costume identity enriched by join.

#### Scenario: Listing scenes of an episode

- **WHEN** a query requests all Scenes of `Episode E`
- **THEN** the read model SHALL return Scenes whose `episode_id = E`, ordered
  by their scene number

#### Scenario: Finding scenes by script day

- **WHEN** a query requests scenes with `script_day = "1. Spieltag"` (or a
  case-insensitive match)
- **THEN** the read model SHALL return all matching scenes across episodes

#### Scenario: Reading costume beats with the scene

- **WHEN** a scene read request is served for a scene with costume beats
- **THEN** the returned view SHALL include the beats resolved with character
  and costume identity, ordered per character
