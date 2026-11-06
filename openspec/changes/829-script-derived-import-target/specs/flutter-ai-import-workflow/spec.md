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

#### Scenario: The locked reason survives an attached target
- **WHEN** the job's target is already attached and the job was applied, or a
  group target is resolved
- **THEN** the card still states WHY the target is locked instead of rendering
  nothing

#### Scenario: A block-less schedule preview can still choose its target
- **WHEN** the payload carries no script block and the job carries no target
  block (a block-less schedule import)
- **THEN** the target actions render without a summary line, so the block can be
  chosen and the apply can become available

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

## MODIFIED Requirements

### Requirement: Raw-Document Job Submission
The workflow SHALL submit schedules (CSV file, PDF file, or pasted
plain text) and scripts (PDF) as RAW-body uploads with the matching
declared `Content-Type` (never multipart), after the season
membership AUTHZ-GATE (capability check before the network call,
`// AUTHZ-GATE:` annotated). A 202 SHALL navigate to the job status
screen; a 200 duplicate SHALL navigate with an explicit "already
imported (duplicate)" callout; 413/415/404 SHALL render copy keyed on
the problem `code`.

The dispatch SHALL send the target it displays: a resolved block target travels
as `X-Active-Block` (with `X-Declared-Season` when the client resolved a season),
and a deliberately block-less dispatch SHALL send `X-Declared-Season` with **no**
`X-Active-Block` — expressed as an explicit per-request opt-out of the ambient
block interceptor, never as a blank or sentinel header value.

#### Scenario: Schedule upload accepted
- **WHEN** the user submits a CSV and the backend returns 202 with a
  job id.
- **THEN** the job status screen pushes with the returned id; the
  submission screen surfaces in-flight progress and never blocks the
  frame on the upload.

#### Scenario: Duplicate document
- **WHEN** the upload returns 200 (digest-duplicate).
- **THEN** the UI navigates to the existing job with the duplicate
  callout; nothing implies a second import was created.

#### Scenario: Membership denial short-circuits
- **WHEN** a user without the costume-dept capability submits.
- **THEN** the client denies before the network call with the 403
  narrative (fake-repository call count of zero in tests).

#### Scenario: Block-less upload carries only the declaration
- **WHEN** the user submits with a target season and no chosen block
- **THEN** the request carries `X-Declared-Season` and no `X-Active-Block`, and
  the job status screen names the target block as not yet chosen with the attach
  action

#### Scenario: A block target is never silently dropped
- **WHEN** the screen resolves a block for the displayed target
- **THEN** the dispatch carries exactly that block in `X-Active-Block`, and a
  season the resolved block does not belong to is refused client-side
  (`ai_import.scope_mismatch`, zero requests)

### Requirement: Tolerant Preview Rendering and Explicit Apply
The preview screen SHALL render the typed `AiImportPreviewResponse` / `AiPreviewPayload` (`kind`/`data`: `script` → `ScriptContext`, `schedule` → `ShootingSchedule`, `merged` → `MergedPreview`; backend issue #337, PR #357) from the generated client: recognized payloads as cards, an unknown future `kind` as an explicit degraded card with a stable code — never silently coerced data, never retyped DTOs. The apply action SHALL submit `ApplyAiImportRequest`
with `draft_ref`s taken verbatim from the preview rows the user acted
on, per-row decisions (Create / Update with the picked aggregate id +
version from the read DTO / skip), the job's PERSISTED episode context
(`episode_id` + `series_id`, stamped onto the cached job row at submit
time — never read from the navigation stack; a missing context requires
the explicit episode picker before the apply dispatch), and the
`accept_as_is` + `edit_distance` values from the actual selection state. The 200 response SHALL render the outcome
summary (`applied_count`, `created_days`, `planned_scene_shoots`).

The apply SHALL additionally require the job's attached target block: while the
job carries no target block the action SHALL be unavailable with the localized
`ai_import.target_missing` copy and a route to the target card, and zero apply
requests SHALL be issued. A `409 ai-import.target-immutable` from a raced attach
SHALL be localized as `ai_import.target_immutable`, naming the block that is
already set when the extension carries it, and SHALL re-render that target.

#### Scenario: Partial preview results
- **WHEN** the preview contains a mix of recognized rows and an
  unknown future `kind`.
- **THEN** recognized rows are actionable; the unknown payload renders as
  a degraded card excluded from one-tap accept-all; apply proceeds only
  with explicit user decisions.

#### Scenario: Unknown preview kind strict-rejects
- **WHEN** the preview carries a `kind` string the client does not know.
- **THEN** the screen renders the standard error state keyed on the
  stable code instead of guessing a meaning (no guessed rendering).

#### Scenario: Apply with mixed decisions
- **WHEN** the user marks one row Create, one Update (existing
  aggregate picked), and skips the rest.
- **THEN** the request carries exactly those mappings; the summary
  card reflects the server's outcome counts; deep navigation to the
  affected episode is offered.

#### Scenario: Apply reconciles after an ambiguous timeout
- **WHEN** an apply dispatch times out with an unknown outcome.
- **THEN** the controller re-reads the job/outcome first and reconciles
  (bounded retry, server-side idempotency per backend issue #338) —
  never blind re-dispatch, never a duplicate import implied.

#### Scenario: Empty preview
- **WHEN** a succeeded job's preview returns 404.
- **THEN** an explicit "no preview available" state renders with the
  option to view the job's terminal status; no fabricated rows.

#### Scenario: No target block means no apply
- **WHEN** the reviewer reaches the apply action on a job that never received a
  target block
- **THEN** the action is unavailable with the localized target-missing copy and
  a route to the target card, and zero apply requests are issued

#### Scenario: A raced attach is explained in place
- **WHEN** the server answers `409 ai-import.target-immutable` with an
  `existing_block_id` extension
- **THEN** the localized copy names that block and the target card re-renders it
