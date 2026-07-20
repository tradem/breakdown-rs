# character-modeling Specification

## Purpose
TBD - created by archiving change introduce-season-block-episode-hierarchy. Update Purpose after archive.
## Requirements
### Requirement: Character is season-scoped
A `Character` SHALL reference exactly one `Season` via a `season_id: SeasonId` field in its created event, replacing the prior `project_id: ProjectId`. The `ProjectId` reference SHALL be removed entirely from the Character context. Season-scoping reflects that Main-Cast Characters persist across the whole season (with their costumes, measurements, and contact info).

#### Scenario: Creating a season-scoped character
- **WHEN** a `CreateCharacter` command is dispatched to a new Character stream
- **THEN** the aggregate SHALL emit `CharacterCreated { id, season_id, name, category, measurements, contact_info, version }` and SHALL NOT carry any `project_id` field

### Requirement: Single CharacterCategory enum replaces bool flags
The `Character` state SHALL use a single `category: CharacterCategory` field in place of the prior `is_main_character: bool` and `is_extra: bool` pair. `CharacterCategory` SHALL be an `enum` with variants `MainCast`, `Guest`, and `Extra`, designed for purely additive extension (adding a variant is backwards-compatible deserialization; removing or renaming a variant is a breaking change requiring a separate proposal).

#### Scenario: Main-cast character
- **WHEN** a Character is created for a season-long role
- **THEN** its `category` SHALL be `CharacterCategory::MainCast`, and no `is_main_character`/`is_extra` bools SHALL exist on the state or events

#### Scenario: Episodic guest role
- **WHEN** a Character is created for a single-Episode role
- **THEN** its `category` SHALL be `CharacterCategory::Guest`

#### Scenario: Extra role
- **WHEN** a Character is created as a background performer (Komparse)
- **THEN** its `category` SHALL be `CharacterCategory::Extra`

#### Scenario: Illegal bool combinations are unrepresentable
- **WHEN** a Character state is constructed
- **THEN** the type system SHALL make `(is_main_character=true, is_extra=true)` impossible to express, because the category is a single enum value

### Requirement: Category is immutable on a Character
A Character's `category` SHALL be set at creation and SHALL NOT be mutable via a dedicated command in this change; changing category requires re-creating the Character. (An additive future `ReclassifyCharacter` command is not precluded but is out of scope.)

#### Scenario: No category mutation command exists
- **WHEN** the Character command surface is inspected
- **THEN** there SHALL be no command that changes `category`; only `UpdateMeasurements` and `UpdateContactInfo` mutation commands SHALL exist alongside `CreateCharacter`

### Requirement: Character appearances are read-model-derived
The query "which Episodes does Character C appear in?" SHALL be answered by a projection join over the existing Scene↔Character assignment relation (Scenes whose `episode_id` resolves to an Episode, joined where the Character is assigned), NOT by a `Vec<EpisodeId>` stored on the Character aggregate. The Character aggregate SHALL NOT store an appearances vector.

#### Scenario: Listing appearances of a character
- **WHEN** a query requests all Episodes in which Character C appears
- **THEN** the read model SHALL derive the set from the scene–character assignment relation joined to Episodes, without reading any vector from the Character aggregate

#### Scenario: Main-cast does not imply every episode
- **WHEN** a `MainCast` Character is not assigned to any Scene of a given Episode
- **THEN** the read model SHALL NOT list that Episode among the Character's appearances (Main-Cast category does not auto-assign to all Episodes)

### Requirement: Measurements and contact info remain on the Character
Measurements (`CharacterMeasurements`) and contact info (`ContactInfo`) SHALL remain fields on the `Character` aggregate and its `CharacterCreated` event. No separate `Actor` aggregate SHALL be introduced in this change; an optional future `actor_id` link is permissible as a non-breaking addition.

#### Scenario: Measurements stored on character
- **WHEN** a `UpdateMeasurements` command targets a Character
- **THEN** the emitted `MeasurementsUpdated` event SHALL carry measurements on the Character stream and SHALL NOT reference any `Actor` entity

### Requirement: Character read model reflects season scoping
The character projection SHALL store `season_id` and `category` and SHALL expose queries by `season_id` and by `category`. Existing queries by `project_id` SHALL be removed.

#### Scenario: Listing main-cast of a season
- **WHEN** a query requests all `MainCast` Characters of `Season S`
- **THEN** the read model SHALL return Characters whose `season_id = S` and `category = MainCast`

