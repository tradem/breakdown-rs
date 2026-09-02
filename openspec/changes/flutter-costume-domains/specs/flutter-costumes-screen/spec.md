<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3 (neuralwatt) -->

# flutter-costumes-screen Specification (delta)

## ADDED Requirements

### Requirement: Costume List and Empty-Bodied Create
The costumes screen SHALL list a season's `CostumeView` rows
(`GET /v1/costumes?season_id=…`) following the reference screen pattern
(family controller, Result repository, Drift cache, reconciliation).
Create SHALL `POST /v1/costumes` with the empty contract body and
immediately offer the first detail/assignment flow so the created row
never dead-ends (documented contract: the create request carries no
fields; contents are added by follow-up commands).

#### Scenario: Creating a costume
- **WHEN** the user confirms Create Costume in the season context.
- **THEN** the empty-body POST dispatches after the session AUTHZ-GATE;
  on 201 the overlay row (server id) renders and the bounded
  reconciliation confirms it; on failure no overlay exists and copy
  keyed on `code` renders.

#### Scenario: Empty costume list
- **WHEN** the season has no costumes.
- **THEN** an empty state with the create affordance renders; it never
  implies costumes exist that do not.

### Requirement: Assignment With Version Echo
Assigning a costume SHALL POST `AssignCostumeRequest` carrying
`character_id` (the picked `CharacterView` id) and the `version` echoed
from the costume row acted on; unassigning SHALL mirror it conforming
to the checked-in body schema (notes echoed unchanged — documented
quirk) with the same version echo. Both commands SHALL apply the
optimistic-after-2xx discipline on the costume row's `character_id` and
surface 409 as "changed elsewhere — refresh" copy keyed on `code`
without auto-retry.

#### Scenario: Assign happy path
- **WHEN** the user picks a character for the costume.
- **THEN** on 2xx the row optimistically carries the assignment and a
  bounded reconciliation swaps it for the projection; the UI never
  blocks on projector lag.

#### Scenario: Optimistic-lock conflict on assign
- **WHEN** the costume changed since the row was read (409).
- **THEN** no optimistic edit is applied (or the edit is rolled back),
  conflict copy renders keyed on `code`, and the client does not
  re-dispatch with a bumped version on its own.

### Requirement: Detail Elements and Notes
The costume detail screen SHALL render the detail elements
(`subject`, `text`, denormalized `category_name`) and allow adding a
detail (`POST …/details`, version echo, category id from the season's
costume-category read DTOs) and editing notes (`PATCH …/notes`).
Costume detail/photo/notes commands SHALL be reflected with the
optimistic-after-2xx discipline on the costume row.

#### Scenario: Adding a categorized detail
- **WHEN** the user adds a detail with subject, text and a category
  picked from the season's categories.
- **THEN** the POST carries ids from the read DTOs acted on; the
  optimistic row edit appears immediately and reconciles via the
  bounded refetch.
