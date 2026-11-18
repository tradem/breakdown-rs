<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3-flash (opencode-go) -->

## ADDED Requirements

### Requirement: Inline Costume Detail Editor

The costume detail surface (identity editor `CostumeDetailPanel` details
section) SHALL edit details **inline in the row** — never in a modal dialog.
`showDialog` SHALL NOT be part of the detail create/edit path.

#### Scenario: create opens in the row

- **WHEN** the user taps the add affordance (`＋ Detail hinzufügen` row,
  key `costume-detail-add-<costumeId>`) at the end of the details list
- **THEN** the inline editor opens in create mode below the row (no dialog
  route), with empty fields and a disabled save action (empty required text)

#### Scenario: edit opens in the row

- **WHEN** the user taps the edit affordance on a detail row
  (key `costume-detail-edit-<detailId>`, tooltip `commonEdit`)
- **THEN** the inline editor opens in edit mode below that row, prefilled
  with the row's `subject` and `text`

#### Scenario: one widget, both modes

- **THEN** create and edit use the SAME editor widget (`_DetailEditor`,
  `initial: CostumeDetailView?`; `null` = create) — no duplicated form, and
  opening one editor closes the previously open one

### Requirement: Detail Row Actions

Every projected costume detail row SHALL expose edit and delete actions in
its trailing slot.

#### Scenario: edit action

- **WHEN** the user taps the row's edit `IconButton`
- **THEN** the inline editor opens prefilled for that detail (same widget
  as create mode), and the page scrolls it into view

#### Scenario: delete action confirms first

- **WHEN** the user taps the row's delete `IconButton`
  (key `costume-detail-delete-<detailId>`, tooltip `commonDelete`)
- **THEN** a confirmation dialog asks for the destructive delete first
  (keys `costume-detail-delete-confirm-<detailId>` on the confirm button,
  `costume-detail-delete-dialog` on the dialog); dispatching happens only
  after confirmation, via the #544 `removeDetail` command.

### Requirement: Required-Field Affordance

The detail editor SHALL make required vs optional fields recognisable up
front, validate eagerly, and gate the save action.

#### Scenario: required text marked

- **WHEN** the editor renders
- **THEN** the `text` field is marked required (asterisk suffix in the
  label + `costumeDetailTextRequiredHint` helper, `"Text ist erforderlich"`)

#### Scenario: optionality consistent

- **AND** the optional `subject` field is marked optional
  (`costumeDetailSubjectOptional` helper) so presence/absence of the
  required marker is unambiguous between the two fields

#### Scenario: eager validation + disabled save

- **WHEN** the user interacts with the text field leaving it empty, or has
  not entered any text yet
- **THEN** the save action is disabled while `text.trim().isEmpty`
  (`onPressed: null`, no post-submit-only error), and after the first user
  interaction the field's `AutovalidateMode.onUserInteraction` shows
  `costumeDetailTextRequired` without requiring a submit
- **AND** a valid text enables save; dispatching calls `updateDetail`
  (edit mode) or `addDetail` (create mode) with the freshest version fence

### Requirement: Stale Projection Comment Correction

Doc comments describing the single-costume enrichment source SHALL match
the current backend behavior.

#### Scenario: enriched list rows

- **WHEN** the `_PhotosSectionState._detail` field (and equivalent data-
  layer comments) explain where `details`/`photos` come from
- **THEN** they document that `list_by_season` batch-enriches pages
  (`enrich_many`, 3 queries per page — details included) since the #543 /
  #544 tranche, not that the list route leaves child collections empty
