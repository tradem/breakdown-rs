## ADDED Requirements

### Requirement: Fundus Isolation Rules
The Costume Aggregate SHALL establish clothing definitions existing independently of assigned actors/roles (fundus-mode), allowing un-scoped usage prior to manual deployment commands.

#### Scenario: Independent fundus item creation
- **WHEN** `CreateCostume` commands fire without holding a valid `character_id` parameter.
- **THEN** the costume generates contextually bound within the project scope without failing validation.

#### Scenario: Attaching notes to an item
- **WHEN** the standard `UpdateCostumeNotes` command passes modifications (e.g. stains or sizing remarks).
- **THEN** the note metadata triggers a `CostumeNotesUpdated` stream update on the item.

### Requirement: Allocation Operations
The Costume Aggregate SHALL rigidly track relations regarding character integration logic.

#### Scenario: Assigning a character to an isolated piece
- **WHEN** an unassigned item processes an `AssignCostumeToCharacter` command.
- **THEN** the `character_id` becomes occupied sending a `CostumeAssignedToCharacter` event.

#### Scenario: Conflict preventing on taken costumes
- **WHEN** `AssignCostumeToCharacter` fires on an actor ID, but the costume already tracks a different occupant.
- **THEN** the runtime fails dispatching a `CostumeError::AlreadyAssigned`.

#### Scenario: Unassigning a Costume
- **WHEN** handling `UnassignCostume` demands on allocated items.
- **THEN** the flag releases to None generating a `CostumeUnassigned` footprint.

### Requirement: Deep Links operations
Costume structures SHALL manage child relationships for descriptive text subsets explicitly.

#### Scenario: Managing Costume Detail Vectors
- **WHEN** executing `AddDetail` and `RemoveDetail` commands
- **THEN** matching list footprints for the items are respectively updated under `DetailAdded` or `DetailRemoved` eventing logic tracking `id` maps.

#### Scenario: Managing External Picture Links
- **WHEN** uploading references calling `LinkPhoto` or unlisting via `UnlinkPhoto`.
- **THEN** the external target UUIDs trigger `PhotoLinked` and `PhotoUnlinked` state transitions.