<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

# flutter-ai-import-workflow Delta (898-ai-import-extract-script-block)

Extends the `771-explicit-ai-import-target` delta (the submit screen resolves and
shows one target; the dispatch declares what it resolved), the
`828` target-card actions (switch / create), and the `829-script-derived-import-target`
delta (block-less upload, late target attach, the preview's own adoption of the
script's block).

## ADDED Requirements

### Requirement: The target card offers "Block extrahieren" as a per-dispatch choice
The import target card SHALL offer a third action, **"Block extrahieren"**, next
to *Block wechseln* and *Block anlegen*, whenever the target season is known and
the season is not in the "no block at all" arm. In that arm the block-less
dispatch is already the only target that exists and applies without a tap, so no
duplicate choice SHALL be offered there.

Choosing the action SHALL mark **this dispatch** as block-less: the upload SHALL
carry `X-Declared-Season` and SHALL omit `X-Active-Block`. The choice SHALL NOT
clear or overwrite the ambient block scope (`activeBlockProvider`), because that
scope is the shell's block pill and the target of other screens.

The choice SHALL be per dispatch and SHALL be cleared by a kind switch and by a
successful dispatch, so a stale choice can never turn a later upload block-less
without the user asking for it.

#### Scenario: A season with a block offers the third action
- **WHEN** the target season resolves to an existing block and the target card renders
- **THEN** the card shows "Block wechseln", "Block anlegen" **and** "Block extrahieren"
- **AND** no block is dropped from the dispatch unless the user chooses the third action

#### Scenario: Choosing "Block extrahieren" dispatches block-less
- **WHEN** the user selects "Block extrahieren" and submits a picked document
- **THEN** the upload carries the declared season and no `X-Active-Block`
- **AND** the ambient block scope is still the block it was before

#### Scenario: The choice does not outlive its dispatch
- **WHEN** a dispatch with the choice has succeeded, or the user switches the document kind
- **THEN** the choice is cleared and the next dispatch carries the resolved block again

#### Scenario: A resolved block still wins by default
- **WHEN** a block is resolved and the user never selects "Block extrahieren"
- **THEN** the dispatch carries that block in `X-Active-Block`

### Requirement: The card states the deferred target while "Block extrahieren" is active
While the choice is active the target line SHALL render the season with the
block stated as unknown (`aiImportTargetUnknownBlock`) together with the
existing block-less hint, and the action SHALL become an **undo** that restores
the resolved line. The card SHALL NOT keep showing the previously resolved block
while the dispatch carries none — the visible target and the dispatched headers
SHALL remain one value.

The undo SHALL restore the resolved line without mutating the ambient scope, so
no restore logic is needed.

#### Scenario: Deferred target is stated, not the previous block
- **WHEN** the user selects "Block extrahieren" on a card that showed `Block 1`
- **THEN** the line reads the season with `Block unbekannt` and the block-less hint
- **AND** the submit affordance stays enabled (the season is the authorization scope)

#### Scenario: Undo restores the resolved line
- **WHEN** the user activates the undo of the "Block extrahieren" action
- **THEN** the line shows the previously resolved block again
- **AND** the ambient block scope is unchanged by the toggle and its undo

### Requirement: After extraction the script's block becomes the target
For a dispatch that chose "Block extrahieren" the client SHALL let the block the
script states become the job's target through the established adoption path: the
block carrying that number SHALL be attached when the target season has it, and
a block with that number SHALL be created and then attached when the season does
not. No second adoption implementation SHALL be introduced for this entry point.

When the script states no block, no number SHALL be invented: the preview SHALL
keep its manual affordances (pick an existing block, or create one by hand).

#### Scenario: The script's block already exists
- **WHEN** the extracted script states `Block 98` and the target season already has a block with number 98
- **THEN** the job's target is attached to that block without a further decision by the user

#### Scenario: The script's block does not exist yet
- **WHEN** the extracted script states `Block 98` and the target season has no block with number 98
- **THEN** a block with number 98 is created in that season and attached as the job's target
- **AND** the created block carries no shooting dates (the script states none)

#### Scenario: A script without a block statement stays undecided
- **WHEN** the extracted document states no block number
- **THEN** no block number is derived from the ambient scope or invented
- **AND** the preview keeps the manual pick/create affordances, and an apply without an attached target is refused with the existing `409 ai-import.target-missing`
