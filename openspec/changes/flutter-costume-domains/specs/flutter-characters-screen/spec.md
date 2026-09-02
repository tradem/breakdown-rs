<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3 (neuralwatt) -->

# flutter-characters-screen Specification (delta)

## ADDED Requirements

### Requirement: Character List and Create
The characters screen SHALL list a season's `CharacterView` rows
(name, category chip over the exhaustive `main_cast|guest|extra`
discriminator) and allow creation (`POST /v1/characters` with
`season_id` from the season read DTO). The list and create SHALL follow
the reference screen pattern (cache, reconciliation, session
AUTHZ-GATE, error copy keyed on `code`). Unknown category values from
future backends SHALL strictly reject the DTO (no guessed meaning).

#### Scenario: Creating a character
- **WHEN** the user submits name + category in the season context.
- **THEN** the POST dispatches after the session gate; the optimstic
      overlay reconciles like the seasons reference; validation errors
      show keyed on `code`.

### Requirement: Contact and Measurements Editors
The character detail screen SHALL provide contact (email/phone) and
measurements (all seven fields) editors performing full-replacement
PATCH commands with the `version` echoed from the read row, prefilled
from the read DTO; 409 SHALL surface "changed elsewhere — refresh"
copy. Empty-string measurement fields SHALL remain valid submissions
(the contract types them as strings; the client adds no client-side
numeric validation it cannot enforce honestly).

#### Scenario: Editing measurements
- **WHEN** the user edits measurements and saves.
- **THEN** the PATCH carries the complete `CharacterMeasurements`
      object plus the version; the row updates optimistically after 2xx
      and reconciles.

#### Scenario: Stale version edit
- **WHEN** another client changed the character first (409).
- **THEN** conflict copy renders; the client offers refresh and never
      re-dispatches with a bumped version automatically.

### Requirement: Scene-Character Binding
The scene detail (Phase 1 scenes screen) SHALL render the scene's
assigned characters resolved from `SceneView.assigned_characters` ids
via the characters projection (read-DTO join only), and SHALL offer
assign (picker over the season's characters; `AssignCharacterRequest`
with the scene `version` from the acted-on `SceneView`) and unassign
(DELETE) with the optimistic-after-2xx discipline on the scene row's
id list.

#### Scenario: Assigning a character to a scene
- **WHEN** the user picks a character in the scene's character picker.
- **THEN** the command carries the character id from the picked read
      DTO and the scene version from the scene DTO; after 2xx the
      assigned list optimistically contains the id and reconciles via
      the scene projection refetch.

#### Scenario: Unassigning a character
- **WHEN** the user removes an assigned character (confirm-first).
- **THEN** the DELETE issues with ids from the read DTO; the row edit
      is optimistic and reconciles; a failed command rolls back the
      local edit and surfaces the error keyed on `code`.
