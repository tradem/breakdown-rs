## ADDED Requirements

### Requirement: Costume is scope-free
A `Costume` SHALL NOT reference any production-level scope (`ProjectId`, `SeasonId`, `BlockId`, or `EpisodeId`). A Costume SHALL carry only `character_id: Option<Uuid>` as its binding to the domain. The prior `project_id: ProjectId` SHALL be removed entirely from the Costume context.

#### Scenario: Creating a scope-free costume
- **WHEN** a `CreateCostume` command is dispatched to a new Costume stream
- **THEN** the aggregate SHALL emit `CostumeCreated { id, character_id, notes, details, photos, version }` and SHALL NOT carry any `project_id` field

### Requirement: Costume binding lives only on character_id
Assignment of a Costume SHALL be expressed solely via the `character_id` link (the existing `CostumeAssignedToCharacter` / `CostumeUnassigned` events, unchanged in shape). Filtering Costumes by production level SHALL be performed in the read model by joining `Costume.character_id → Character.season_id` (or further to Episode via appearances), not by any scope field on the Costume itself.

#### Scenario: Filtering costumes by season
- **WHEN** a query requests all Costumes for a given Season
- **THEN** the read model SHALL resolve them by joining `costumes.character_id` to `characters.season_id`; the Costume aggregate and Costumes events SHALL carry no Season reference

#### Scenario: Assigning a costume to a character
- **WHEN** an `AssignCostumeToCharacter { id, character_id, version }` command targets an unassigned Costume
- **THEN** the aggregate SHALL emit `CostumeAssignedToCharacter { id, character_id, version }`, unchanged in shape from the pre-change design

### Requirement: Costume read model omits project_id
The costume projection SHALL store `character_id` and SHALL NOT store any `project_id`, `season_id`, `block_id`, or `episode_id` column. Existing queries by `project_id` SHALL be removed.

#### Scenario: Projection schema
- **WHEN** the costume projection schema is inspected
- **THEN** it SHALL contain `id`, `character_id`, `notes`, `details`, `photos`, `version` and SHALL NOT contain any production-scope identifier
