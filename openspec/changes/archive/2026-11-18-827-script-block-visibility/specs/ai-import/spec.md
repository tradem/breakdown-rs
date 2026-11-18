<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

# ai-import Delta (827-script-block-visibility)

## ADDED Requirements

### Requirement: The import SHALL read the block the script states

A script extraction SHALL read the production block number out of the document's
page headers, independently of the block that was active at upload:

- The deterministic scan SHALL accept the observed header shapes — `Block: 2`,
  `Block 2`, and the glued `Block: 098/Ep.: 294` — reading the **leading digits
  only** (everything after a `/` belongs to the next field).
- The scan SHALL be shape-driven rather than casing-driven: page headers also
  arrive in capitals, while `Block` capitalizes in German prose too. A marker
  SHALL therefore require 1-3 digits, a non-alphanumeric digit boundary, and a
  field boundary behind the number (end of line, a `/`/`|`/`·` separator, or an
  uppercase letter starting the next header field). Prose and scene headings
  SHALL NOT parse.
- The scan SHALL cost no LLM tokens.
- Page headers repeat the marker on every page; the FIRST occurrence SHALL win,
  and a repeated header SHALL NOT flip the published value.
- When the deterministic scan finds no marker, the extraction SHALL accept the
  model's answer as a fallback, which requires the field to be declared in the
  provider-facing strict schema (a prompt rule without a schema field is
  unreachable under `strict` Structured Outputs).

#### Scenario: A page header states the block on every page

- **GIVEN** a script whose pages are headed `Block: 2   Ep.: 3 (Der Unfall)`
- **WHEN** the extraction runs
- **THEN** every progress frame names block `2`
- **AND** the stored preview carries `block_number: 2`

#### Scenario: The header glues the block and the episode

- **GIVEN** a page header `Block: 098/Ep.: 294`
- **WHEN** the scan reads it
- **THEN** the block is `98`
- **AND** the episode is `294` (the suffix is never part of either number)

#### Scenario: Prose mentions a block, the header states none

- **GIVEN** a script whose body says `Block 2 wurde am Montag gedreht.`
- **WHEN** the scan runs
- **THEN** no block is published (`block_number` stays absent)
- **AND** no block number is inferred from the episode or the scene numbering

### Requirement: The script's block SHALL be published separately from the import target

`AiImportProgress` SHALL carry the block the script states as its own additive,
nullable field, distinct from the job's import target:

- `block_number: Option<i32>`, additive with `serde(default)`, so frames and
  previews written before the field existed deserialize as `None`.
- `None` SHALL mean "the script does not state a block" — never a fabricated
  number and never the target echoed back.
- The import target (`AiImportTarget.block_number`) SHALL keep meaning "the block
  this import writes into"; this change SHALL NOT alter the target.
- A client SHALL render the two side by side and flag a mismatch non-blocking.

#### Scenario: The script disagrees with the target

- **GIVEN** a job whose target block is `1` and a script headed `Block: 2`
- **WHEN** the client renders the progress or preview surface
- **THEN** both numbers are visible ("Skript: Block 2 · Importziel: Block 1")
- **AND** the mismatch is flagged without blocking the apply

#### Scenario: The script states no block

- **GIVEN** a script without a block marker and a job whose target block is `1`
- **WHEN** the client renders the scope line
- **THEN** the target is shown as the associated block with explicit wording
- **AND** no number is invented for the script
