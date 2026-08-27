<!--
  Authors: Tobias Rademacher (@tradem) — domain stakeholder & spec author
           glm-5.2 (neuralwatt) — coding agent / co-author
  Note: OpenSpec does not natively track authorship; this header is a manual addition.
-->

## MODIFIED Requirements

### Requirement: Scene is scoped to an Episode
A `Scene` SHALL reference exactly one `Episode` via an `episode_id: EpisodeId` field in its created event, replacing the prior `project_id: ProjectId`. The `ProjectId` reference SHALL be removed entirely from the Scene context. A Scene SHALL additionally carry an optional `summary: Option<String>` within `SceneDetails` for free-form scene description. `SceneDetails` SHALL additionally carry an optional `script_day: Option<String>` representing the fictional script-chronology day (e.g. "1. Spieltag"), which is distinct from the calendar `ShootingDay.date` and is used as a free-form search index for finding scenes by script-day later. `script_day` has no further domain semantics.

#### Scenario: Creating a scene scoped to an episode
- **WHEN** a `CreateScene { id, episode_id, details, assigned_characters }` command is dispatched to a new Scene stream where `details.summary` may be `Some(String)` or `None` and `details.script_day` may be `Some(String)` or `None`
- **THEN** the aggregate SHALL emit `SceneCreated { id, episode_id, details, assigned_characters, version }` where `details` carries `summary` and `script_day`, and SHALL NOT carry any `project_id` field

### Requirement: Scene read model reflects episode scoping
The scene projection SHALL store `episode_id` and SHALL expose queries for Scenes by `episode_id`. Existing queries by `project_id` SHALL be removed. The scene projection SHALL additionally store `script_day` and SHALL expose queries for Scenes by `script_day` (exact or case-insensitive like match).

#### Scenario: Listing scenes of an episode
- **WHEN** a query requests all Scenes of `Episode E`
- **THEN** the read model SHALL return Scenes whose `episode_id = E`, ordered by their scene number

#### Scenario: Finding scenes by script day
- **WHEN** a query requests scenes with `script_day = "1. Spieltag"` (or a case-insensitive match)
- **THEN** the read model SHALL return all matching scenes across episodes
