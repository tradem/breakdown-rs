<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3 (neuralwatt) -->

# flutter-ai-import-workflow Delta (771-explicit-ai-import-target)

## ADDED Requirements

### Requirement: The submit screen shows the import target before dispatch
The AI-import submit screen SHALL render the write target — `Season {n} ·
Block {n}` — above the submit action, beside the AI disclosure. The season
number SHALL be resolved cache-only (an uncached one renders the explicit
`aiImportTargetUnknownSeason` narrative), the block number SHALL come from the
resolved scope (`aiImportTargetUnknownBlock` when absent). No number is ever
fabricated, and the target card SHALL state the consequence (the imported rows
land in that block).

#### Scenario: A resolved target is visible
- **WHEN** the screen has a season context and its block scope is resolved
- **THEN** the target card renders `Staffel 2 · Block 3` above the submit action

#### Scenario: An uncached season number degrades
- **WHEN** the target season is not in the seasons cache
- **THEN** the line renders `Staffel unbekannt · Block 3` — never a guessed
  number

### Requirement: The target is resolved deliberately, never ambiently
The screen SHALL resolve the target from the one season context the dispatch
also uses (the entry point's explicit season, else the ambient scope's season):

- exactly one block in the season → adopted automatically, writing the sticky
  scope so the header and the visible line agree;
- several blocks → an inline picker, one row per block, whose pick writes the
  sticky scope;
- no block → the upload is blocked with the actionable "create a block first"
  copy;
- block-list fetch failure → the code-keyed error copy with a retry affordance;
- no season context → the upload is blocked with the "select a season first"
  copy.

The submit action SHALL be disabled whenever no target is resolved.

#### Scenario: A wizard entry with one block needs no manual scope switch
- **WHEN** the wizard CTA opens the screen with the created season and that
  season has exactly one block
- **THEN** the block is adopted, the target line names it, and the dispatched
  upload carries it in `X-Active-Block`

#### Scenario: Several blocks require an explicit pick
- **WHEN** the target season has more than one block
- **THEN** the picker renders, the submit action stays disabled, and a pick
  publishes the target line and adopts the scope

#### Scenario: No block blocks the upload
- **WHEN** the target season has no block
- **THEN** the "create a block first" copy renders and the submit action is
  disabled (zero requests on any tap attempt)

### Requirement: The dispatch declares its target and refuses a contradiction
The dispatch SHALL send the resolved target season as `X-Declared-Season`, and
SHALL refuse a target season the active block does not belong to with the scoped
code `ai-import.scope-mismatch` (409) **before** any request — the same code the
server answers, so one narrative covers both provenances and the upload never
writes into a season the user was not shown.

#### Scenario: A foreign ambient block is refused client-side
- **WHEN** the screen resolved season B as the target while the active block
  belongs to season A
- **THEN** the dispatch returns `ai_import.scope_mismatch`, renders its localized
  copy, and issues zero repository calls

#### Scenario: A matching target is declared
- **WHEN** the target season owns the active block
- **THEN** the upload is dispatched and carries `X-Declared-Season` with that
  season

### Requirement: The job view repeats the recorded target
The job status screen SHALL render the job's server-snapshotted target
(`AiImportJob.target`) as `Season {n} · Block {n}`. A job without a snapshot —
a pre-#771 row, or a fresh upload whose season read degraded to `null` — SHALL
render the explicit, CAUSE-NEUTRAL "not recorded" narrative instead of a guessed
season or an invented cause.

#### Scenario: A recorded target is shown
- **WHEN** the status screen renders a job whose `target` is
  `{season_number: 2, block_number: 3}`
- **THEN** the target card reads `Staffel 2 · Block 3`

#### Scenario: A job without a snapshot states the absence
- **WHEN** the job's `target` is `null`
- **THEN** the card reads `Ziel nicht aufgezeichnet.` — it names no cause,
  because a fresh upload whose season read failed is indistinguishable here
