<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->

# ai-import

## ADDED Requirements

### Requirement: Acknowledgement set semantics

An uncertainty acknowledgement SHALL be identified by its
`(scene_index, field)` pair, and that pair SHALL be the entire payload. A
repeated pair in `ApplyAiImportRequest.uncertainty_acknowledgements` SHALL be
**idempotent**: the API edge SHALL NOT refuse the request, because the
acknowledgement list is set-shaped by nature (the apply gate matches
acknowledgements by pair, and no ordering or last-write semantics exist to
lose). Every acknowledgement — including a repeat — SHALL still be validated
against the stored preview: an acknowledgement that references no blocking
uncertainty the preview carries SHALL be refused as a client bug.

#### Scenario: A repeated acknowledgement applies successfully

- **WHEN** an apply request carries the same `(scene_index, field)` pair twice
  and that pair is a blocking `field_ambiguity` of the stored preview
- **THEN** the request is accepted and reaches the apply worker
- **AND** no `422 domain.validation` is returned for the repetition

#### Scenario: A repeat cannot smuggle in an unknown pair

- **WHEN** an apply request repeats a pair the preview does not carry as a
  blocking uncertainty
- **THEN** the request is refused before any command is dispatched

#### Scenario: Duplicate pairs do not over-acknowledge

- **WHEN** a preview carries several blocking entries for one pair and the
  request acknowledges that pair
- **THEN** every entry of that pair counts as acknowledged by the gate
