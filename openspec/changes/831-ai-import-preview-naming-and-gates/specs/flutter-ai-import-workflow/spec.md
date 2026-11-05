<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

# flutter-ai-import-workflow

## ADDED Requirements

### Requirement: The preview header names the provider/model the job USED

The preview's naming card SHALL name the provider/model pair the import job
actually ran with, sourced from the job's content-free telemetry
(`AiImportJob.telemetry`), as its primary line. The card SHALL NOT render the
currently configured pair as its primary line, and SHALL NOT repeat the same
pair in a second line or caption.

The configured pair SHALL render as a second, subordinate line ONLY when it
differs from the used pair by provider or by model; when the two agree the card
renders no second line. The comparison SHALL be made over the rendered pair
labels, so a wire value carrying only one half of the pair never produces a
partially-empty difference claim.

The telemetry snapshot SHALL be read through the job snapshot route
(`getJobAndCache`), never through the SSE watch and never through a second
projection lookup, and the app's single SSE consumer SHALL remain the job-status
controller.

#### Scenario: The configured model differs from the used one

- **WHEN** the job's telemetry records `mistral-large-3` at `eurouter` and the
  caller's configuration names `assistant-model-1` at `openai`
- **THEN** the card's primary line names `mistral-large-3 (eurouter)` as the
  model used
- **AND** a second line names `assistant-model-1 (openai)` as the currently
  configured, differing model
- **AND** no third line repeats the configured pair

#### Scenario: The configured model equals the used one

- **WHEN** the job's telemetry and the caller's configuration name the same
  provider and model
- **THEN** the card renders exactly one line — the used pair
- **AND** no "differs" line and no configured caption render

#### Scenario: A job without telemetry claims no comparison

- **WHEN** the job recorded no telemetry (a pre-#609 row) or the snapshot cannot
  be read
- **THEN** the card names no used model
- **AND** it names the configured pair once, in wording that states the pair is
  currently configured rather than used
- **AND** it renders no "differs" line

#### Scenario: A used pair survives an unconfigured account

- **WHEN** the job's telemetry records a pair but the account has no
  configuration (deleted after the import, or the discovery failed)
- **THEN** the card still names the used pair
- **AND** it claims no comparison

#### Scenario: No invented names

- **WHEN** the account is unconfigured AND the job recorded no telemetry
- **THEN** the card renders the existing "no AI configuration" copy
- **AND** no provider or model name is rendered at all

### Requirement: The episode picker renders only while the apply context is missing

The apply card SHALL render the episode-picker affordance
(`ai-apply-pick-episode`) ONLY while the apply context is unresolved, together
with the missing-context notice that explains it. With a resolved context the
card SHALL render nothing under the submit button, and the
`state.context == null` recovery SHALL stay reachable.

#### Scenario: A resolved context shows no stray picker

- **WHEN** the preview opens with a persisted apply context
- **THEN** the apply card renders no `ai-apply-pick-episode` affordance
- **AND** nothing else is rendered between the submit button and the card's end

#### Scenario: A missing context still offers the picker

- **WHEN** the job carries no apply context
- **THEN** the apply card renders the missing-context notice AND the picker
  affordance beside it
- **AND** the submit button stays disabled until an episode is picked

### Requirement: The import submit action requires a picked document

The submit affordance SHALL stay disabled (`onPressed: null`) until a document
is picked, for both the script and the schedule flow, and SHALL disable again
once a successful submit clears the pending document. The in-dispatch
missing-document guard SHALL remain as a backstop that is not reachable from the
UI. The file row's "no file picked" line SHALL provide the visible explanation
of the disabled state.

#### Scenario: No file picked

- **WHEN** the screen opens (no document in the pending-document state) with a
  resolved target
- **THEN** the submit affordance is disabled
- **AND** the file row states that no file is picked
- **AND** zero uploads are dispatched in either kind

#### Scenario: A file is picked, then cleared

- **WHEN** a document is picked
- **THEN** the submit affordance becomes enabled (given a resolved target)
- **AND** it disables again when the pending document is cleared (a kind switch,
  or a completed submit)
