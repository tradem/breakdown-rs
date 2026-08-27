## ADDED Requirements

### Requirement: Character Management State Handling
The Character aggregate SHALL model the actors/extras representing roles within a Project via Event Sourcing semantics, parsing a mixture of contact-identifiers God-Commands and individual physical measurements.

#### Scenario: Creating a Character Role
- **WHEN** a user dispatches a `CreateCharacter` Command containing `project_id`, `name`, `is_extra` and `is_main_character` flags.
- **THEN** the mailbox applies a `CharacterCreated` event payload initializing a state model carrying the variables.

#### Scenario: Updating bulk measurement sets (God Command)
- **WHEN** a user dispatches an `UpdateMeasurements` payload with physical fields (shoe sizes, hat size, etc).
- **THEN** the system validates if parameters have physically changed, then dispatches the `MeasurementsUpdated` event mapping decimal values across all configured fields simultaneously.

#### Scenario: Modifying Contact Info
- **WHEN** a user dispatches an `UpdateContactInfo` Command representing phone/e-mail shifts.
- **THEN** the actor emits a `ContactInfoUpdated` replacing the current dataset context in the aggregate map.