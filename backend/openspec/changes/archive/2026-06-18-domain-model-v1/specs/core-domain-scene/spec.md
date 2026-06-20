## ADDED Requirements

### Requirement: Scene Registration
The Scene Aggregate SHALL act as the bounded representation of filming situations occurring throughout a production cycle, grouping content descriptors and actor linkages.

#### Scenario: Instantiation of Scenes
- **WHEN** a `CreateScene` payload is processed enclosing numbers, location motifs, and mood identifiers (IN/AT/DA)
- **THEN** the context yields a `SceneCreated` flag starting the bounded context history.

#### Scenario: Bulk form overrides
- **WHEN** users shift the content properties or schedule flags using `UpdateSceneDetails`
- **THEN** the structural properties are overwritten simultaneously mimicking standard UI data posts, triggering a `SceneDetailsUpdated` tracking payload.

### Requirement: Scene Relations Management
The aggregate SHALL separate relational data inputs into explicit functional workflows, distinctly removed from basic text edits.

#### Scenario: Linking a character
- **WHEN** `AssignCharacter` commands occur with a given UUID pointing to an actor entity.
- **THEN** if valid, the context registers `CharacterAssigned` pushing the pointer into its `assigned_characters` vector cache.

#### Scenario: Removing linked roles
- **WHEN** `RemoveCharacter` demands a clean-up.
- **THEN** the ID is purged inside the Event payload via a `CharacterRemoved` flag mapping.