<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

# flutter-ai-import-workflow Delta (829-script-derived-import-target)

Extends the `771-explicit-ai-import-target` delta (the submit screen shows and
resolves its target; the dispatch declares what it resolved) and consumes issue
#827's script block (`AiImportProgress.block_number` /
`ScriptContext.block_number`) and issue #828's target-card actions.

## ADDED Requirements

### Requirement: The target card adopts the script's block, and creates it when missing
The import target card SHALL offer adopting the block the script states (issue
#827's value) as the import target, labelled with the block number
(`aiImportTargetAdoptScriptBlock`, e.g. "Aus Skript übernehmen – Block 2"), from
the state in which the client knows both the script's block and a target season.

Adoption SHALL resolve the block number to a block of the target season through
the block list the card already fetches. When the target season has no block with
that number, the affordance SHALL become "Block anlegen"
(`aiImportTargetCreateBlock`) routing into the existing create-block sheet
(`showCreateBlockSheet`) with the number prefilled, and SHALL adopt the freshly
created block.

Both paths SHALL go through **one** seam — the job's target attach (see the
`ai-import` delta) — so the value the card renders, the value the apply guard
uses and the value the job view reports cannot differ. No affordance SHALL submit
a block id that the seam did not accept, and no dead end SHALL remain: every
target state renders either an action or an honest explanation.

#### Scenario: The script's block exists in the target season
- **WHEN** the script states block 2, the target season has a block 2 and the
  job has no attached target
- **THEN** the card offers "Aus Skript übernehmen – Block 2", and tapping it
  attaches that block and re-renders the target line as `Staffel {n} · Block 2`

#### Scenario: The script's block must be created first
- **WHEN** the script states block 2 and the target season has no block 2
- **THEN** the card offers "Block anlegen", opens the create-block sheet with
  number 2 prefilled, and the created block becomes the attached target

#### Scenario: The script states no block
- **WHEN** the extracted script carries no block number
- **THEN** no adopt affordance renders, and the card keeps the switch/create
  actions from the #828 contract — the association is stated, not omitted

### Requirement: A block-less dispatch sends no target block and declares its season
The submit dispatch SHALL be able to upload with **no** `X-Active-Block`. Because
`ActiveBlockInterceptor` attaches the ambient header to every request, the
dispatch SHALL use an explicit per-request opt-out rather than a blank or
sentinel header value, and SHALL always send `X-Declared-Season`.

The submit action's guard SHALL keep holding: a resolved block target is
dispatched with `X-Active-Block` (today's behaviour, including the client-side
`ai_import.scope_mismatch` refusal), and a block-less dispatch is only offered
where the client deliberately resolves a season without a block. In both cases
the season the user sees SHALL be the season that is sent.

#### Scenario: A block-less upload carries only the declaration
- **WHEN** the dispatch runs with a target season and no chosen block
- **THEN** the request carries `X-Declared-Season` and no `X-Active-Block`, and
  the resulting job is rendered as "target block not chosen yet"

#### Scenario: The existing mismatch refusal is untouched
- **WHEN** the resolved block belongs to a different season than the displayed
  target season
- **THEN** the dispatch is still refused with `ai_import.scope_mismatch` and
  zero requests are issued

### Requirement: The in-preview episode creation anchors on the effective target
The in-preview episode creation (the review-time `POST /v1/episodes` that makes a
group's episode exist in the import's block) SHALL anchor on the job's
**effective** target block — the attached block when one is attached — and never
on the block that merely happened to be active at upload.

While the job has no target block, the creation SHALL be disabled with an honest
reason (`aiImportTargetUnknownBlock` or the attach narrative) instead of failing
at the call. A successful attach SHALL make the creation available without a
manual reload.

#### Scenario: Creation waits for the target
- **WHEN** a reviewer opens the preview of a block-less, unattached job and the
  preview expects a group episode
- **THEN** the create affordance is disabled with the target-missing narrative
  and issues zero requests

#### Scenario: Creation follows the attached block
- **WHEN** the target has been attached and the reviewer creates that group's
  episode
- **THEN** the episode is created inside the attached block and adopted as the
  group target

### Requirement: The target freezes once a group episode is resolved
Once any preview group has been resolved to an existing episode — by adoption or
by the in-preview creation — the target card SHALL render read-only with the
reason (`aiImportTargetFrozen`), offering neither switch, create nor adopt. It
SHALL explain that the preview's episode choice is block-bound and that a
different target needs a new import.

#### Scenario: A resolved preview locks its target
- **WHEN** the reviewer has created or adopted the episode of any group
- **THEN** the target card shows the locked state with its reason and offers no
  target action

#### Scenario: The lock is explained, not silent
- **WHEN** the locked card is rendered
- **THEN** it names the cause and states that changing the target requires a new
  import — never a bare disabled control

### Requirement: The apply names a missing target instead of guessing
The apply action SHALL NOT be offered (or SHALL be refused with localized copy,
keyed on the problem `code`) while the job has no attached target block: the
server's `409 ai-import.target-missing` SHALL be localized as `ai_import.target_missing`
and SHALL route to the target card, and `409 ai-import.target-immutable` SHALL be
localized as `ai_import.target_immutable` naming the block that is already set
when the extension carries it. The client SHALL never apply into an episode that
silently becomes the target.

#### Scenario: No target means no apply
- **WHEN** the reviewer reaches the apply action on a job without an attached
  target
- **THEN** the apply is unavailable with the localized target-missing copy and a
  route to the target card, and zero apply requests are issued

#### Scenario: A raced attach is explained
- **WHEN** the server answers `409 ai-import.target-immutable` with
  `existing_block_id`
- **THEN** the localized copy names the block that is already set and the card
  re-renders that target

#### Scenario: The two new codes are localized in both locales
- **WHEN** the problem codes `ai-import.target-missing` and
  `ai-import.target-immutable` are rendered
- **THEN** `de` and `en` ARB catalogs both carry the copy and the ARB key-parity
  check passes
