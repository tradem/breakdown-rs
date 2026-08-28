# scene-scoping Specification

## Purpose
TBD - created by archiving change introduce-season-block-episode-hierarchy. Update Purpose after archive.
## Requirements
### Requirement: Scene is scoped to an Episode
A `Scene` SHALL reference exactly one `Episode` via an `episode_id: EpisodeId` field in its created event, replacing the prior `project_id: ProjectId`. The `ProjectId` reference SHALL be removed entirely from the Scene context. A Scene SHALL additionally carry an optional `summary: Option<String>` within `SceneDetails` for free-form scene description.

#### Scenario: Creating a scene scoped to an episode
- **WHEN** a `CreateScene { id, episode_id, details, assigned_characters }` command is dispatched to a new Scene stream where `details.summary` may be `Some(String)` or `None`
- **THEN** the aggregate SHALL emit `SceneCreated { id, episode_id, details, assigned_characters, version }` where `details` carries `summary`, and SHALL NOT carry any `project_id` field

### Requirement: Scene read model reflects episode scoping
The scene projection SHALL store `episode_id` and SHALL expose queries for Scenes by `episode_id`. Existing queries by `project_id` SHALL be removed.

#### Scenario: Listing scenes of an episode
- **WHEN** a query requests all Scenes of `Episode E`
- **THEN** the read model SHALL return Scenes whose `episode_id = E`, ordered by their scene number

### Requirement: Scene commands and events carry no project_id
No `Scene` command (`CreateScene`, `UpdateSceneDetails`, `AssignCharacter`, `RemoveCharacter`) or `SceneEvent` variant SHALL contain a `project_id` field. All references SHALL be `episode_id` (on creation) or `id` (on mutation, scoped to the aggregate stream).

#### Scenario: Mutation commands are unscoped by production
- **WHEN** an `UpdateSceneDetails { id, details, version }` command is dispatched
- **THEN** the emitted `SceneDetailsUpdated` event SHALL carry only `id`, `details`, `version` — no production-level scope field

