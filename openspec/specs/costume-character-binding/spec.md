# costume-character-binding Specification

## Purpose
TBD - created by archiving change introduce-season-block-episode-hierarchy. Update Purpose after archive.
## Requirements
### Requirement: Costume is scope-free
A `Costume` SHALL NOT reference any production-level scope (`ProjectId`, `SeasonId`, `BlockId`, or `EpisodeId`). A Costume SHALL carry `character_id: Option<Uuid>` and `category_id: Option<CostumeCategoryId>` as its bindings to the domain (issue #543: the n:1 category reference is structurally identical to `character_id` — both are season-scoped aggregates referenced from the scope-free costume, both resolved by join in the read model). The prior `project_id: ProjectId` SHALL be removed entirely from the Costume context.

#### Scenario: Creating a scope-free costume
- **WHEN** a `CreateCostume` command is dispatched to a new Costume stream
- **THEN** the aggregate SHALL emit `CostumeCreated { id, character_id, notes, details, photos, version }` and SHALL NOT carry any `project_id` field

### Requirement: Costume binding lives on character_id and category_id

Assignment of a Costume SHALL be expressed via the `character_id` link (the
existing `CostumeAssignedToCharacter` / `CostumeUnassigned` events, unchanged
in shape); its single vocabulary category via the `category_id` link
(`SetCostumeCategory` / `CostumeCategorySet`, issue #543). `character_id` is
the costume's **primary/default** character binding; it does not constrain
where the costume may be worn. Neither field is a scope column: filtering
Costumes by production level SHALL be performed in the read model by joining
`Costume.character_id → Character.season_id` (or further to Episode via
appearances), and which season's category vocabulary applies SHALL be derived
from the same join — never by any scope field on the Costume itself. This
holds for AI-created costumes as well: the import path SHALL NOT introduce a
season, episode or scene scope **column** on the Costume, and an AI-created
costume SHALL be reachable through exactly the same queries as a manually
created one. An imported costume is deliberately left **uncategorised** (the
import chain never dispatches `SetCostumeCategory`) — users categorise it
later through the costume category picker. Per-scene casting is a
**scene-side** relation (ordered costume beats on the Scene aggregate, see
`scene-costume-assignment`), not a field on the Costume: a character may wear
different costumes in different scenes, and more than one costume within a
single scene. The `costume.already-assigned` conflict applies to the primary
binding only — a costume already bound to another character cannot be
re-bound without unassigning, but that in no way limits the costume being
cast for other characters in scene costume beats.

#### Scenario: Filtering costumes by season

- **WHEN** a query requests all Costumes for a given Season
- **THEN** the read model SHALL resolve them by joining
  `costumes.character_id` to `characters.season_id` (and/or the repertoire
  rows); the Costume aggregate and Costume events SHALL carry no Season
  reference and no Scene reference

#### Scenario: Assigning a costume to a character

- **WHEN** an `AssignCostumeToCharacter { id, character_id, version }`
  command targets an unassigned Costume
- **THEN** the aggregate SHALL emit
  `CostumeAssignedToCharacter { id, character_id, version }`, unchanged in
  shape from the pre-change design

#### Scenario: An AI-imported costume is listed like a manual one

- **WHEN** a costume created by an AI import has been bound to a character
- **THEN** it SHALL appear in the same season-scoped costume query as a
  manually created costume
- **AND** it SHALL carry no additional scope field identifying its import
  origin

#### Scenario: Primary binding does not restrict scene casting

- **WHEN** a scene costume beat casts a costume whose primary `character_id`
  differs from the beat's character
- **THEN** the beat SHALL be accepted (no 409, no aggregate error) — the
  primary binding names the default wearer, the scene names the actual one
- **AND** the costume-counting rules of the wardrobe views SHALL still key on
  the primary `character_id`

### Requirement: An AI-created costume is created unassigned and then bound
A `Costume` created by an AI script import SHALL be created **without** a
`character_id` and SHALL be bound via the existing `AssignCostumeToCharacter`
command against the `Character` identified by the costume's character name,
deduplicated across the preview by normalised name identity (see `ai-import`).
Its extracted description SHALL be carried by `UpdateCostumeNotes`, because
`CreateCostume` accepts no description. The creation order mirrors the write path
that already applies to photos on an unassigned costume, and it keeps a costume
that cannot be bound from silently existing without an owner.

#### Scenario: Import creates a costume for a scene character
- **WHEN** a draft row is applied and carries a costume for a figure the preview
  created
- **THEN** `CreateCostume` SHALL be dispatched with no `character_id`
- **AND** `UpdateCostumeNotes` SHALL carry the extracted description
- **AND** `AssignCostumeToCharacter` SHALL bind it to that figure's `Character`
- **AND** the resulting `Costume` SHALL carry only `character_id` as its scope
  link (`category_id` stays unset — the import is deliberately
  category-less), unchanged from the manual creation path

#### Scenario: Binding a freshly created costume uses the created version
- **WHEN** the apply binds a costume it has just created
- **THEN** `AssignCostumeToCharacter` SHALL carry the version `CreateCostume`
  returned
- **AND** a replayed bind SHALL be refused as a version mismatch rather than
  performing a second assignment

#### Scenario: Binding fails after the costume was created
- **WHEN** `AssignCostumeToCharacter` is rejected for a freshly created costume
- **THEN** the costume SHALL remain unassigned and visible as unassigned
- **AND** the apply SHALL report the row as partially applied with the reason
- **AND** the retry SHALL reuse the same costume id (mapping row) instead of
  creating a second one

### Requirement: Costume read model omits project_id
The costume projection SHALL store `character_id` and the costume-level category (`category_id`, `category_name` — issue #543) and SHALL NOT store any `project_id`, `season_id`, `block_id`, or `episode_id` column. Existing queries by `project_id` SHALL be removed.

#### Scenario: Projection schema
- **WHEN** the costume projection schema is inspected
- **THEN** it SHALL contain `id`, `character_id`, `category_id`, `category_name`, `notes`, `details`, `photos`, `version` and SHALL NOT contain any production-scope identifier

