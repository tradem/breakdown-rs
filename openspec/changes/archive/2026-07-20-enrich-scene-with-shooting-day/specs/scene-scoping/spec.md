## MODIFIED Requirements

### Requirement: Scene is scoped to an Episode
A `Scene` SHALL reference exactly one `Episode` via an `episode_id: EpisodeId` field in its created event, replacing the prior `project_id: ProjectId`. The `ProjectId` reference SHALL be removed entirely from the Scene context. A Scene SHALL additionally carry an optional `summary: Option<String>` within `SceneDetails` for free-form scene description.

#### Scenario: Creating a scene scoped to an episode
- **WHEN** a `CreateScene { id, episode_id, details, assigned_characters }` command is dispatched to a new Scene stream where `details.summary` may be `Some(String)` or `None`
- **THEN** the aggregate SHALL emit `SceneCreated { id, episode_id, details, assigned_characters, version }` where `details` carries `summary`, and SHALL NOT carry any `project_id` field
