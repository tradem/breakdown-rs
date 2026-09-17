<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3 (neuralwatt) -->
<!-- Co-authored-by: omen-alpha (opencode-go) -->

# flutter-season-setup-wizard Specification

## Purpose
Defines the guided production setup surface of the Flutter client: the
linear four-step season setup wizard (Season → Blocks → Review →
Completion) — smart-default season number with live preview, repeatable
block drafts with template suggestions, the review summary, sequential
dispatch of the existing create commands with per-command progress and
the optimistic-after-2xx + bounded-retry reconciliation discipline,
destructive abort with confirmation (no draft persistence, no resume),
the partial-failure surface with in-session retry, and the conditional
AI-import completion CTA gated on the existing AI-configuration read.

## Requirements


### Requirement: Linear Setup Wizard Steps
The season setup wizard SHALL guide the user through linear steps —
Season, Blocks, Review, Completion — with a visible progress
indicator ("Schritt x von n") and forward/back navigation between
steps. Each step SHALL validate its own inputs before enabling
"Weiter": the season number is a positive integer (default
smart-filled as highest existing +1), block episode counts are
positive integers, at least one block draft exists at submit time.

#### Scenario: Smart season number default
- **WHEN** the user opens the wizard with seasons 1 and 2 existing.
- **THEN** the number field defaults to 3 with a live preview of
  the resulting season title.

#### Scenario: Invalid step blocks forward navigation
- **WHEN** the Blocks step has zero block drafts or a zero episode
  count.
- **THEN** "Weiter" is disabled with inline validation copy keyed
  per error code (no platform exception surfaces).

### Requirement: Block Draft With Templates
The Blocks step SHALL let the user add, edit, and remove block
drafts (episode count, optional title) and SHALL offer block
templates as suggestions (e.g. "4 Blöcke à 8 Episoden", "3 Blöcke
à 6 Episoden") that expand into drafts. Global region rules for
episodes and titles derive from validation error codes that surface
as inline copy (conflicts reported against the season under
creation).

Block and episode numbers are NOT user fields: the backend
enforces `(series_id, number)` uniqueness for both blocks
(`idx_projection_block_series_number`) and episodes
(`idx_projection_episode_series_number`), so the wizard SHALL
derive the first free series-scoped numbers at wizard open from the
series' existing projections (`max + 1` — the same client-side
append-order derivation discipline as `nextOrderKey`), render them
as read-only headlines, and dispatch the drafts' episodes
plan-sequentially (a retry reproduces the acked numbers exactly).

#### Scenario: Applying a template
- **WHEN** the user selects the "4 Blöcke à 8 Episoden" template.
- **THEN** four block drafts with episode count 8 each are added,
  each individually editable afterwards.

#### Scenario: Removing a draft
- **WHEN** the user removes a block draft.
- **THEN** the draft list updates and the wizard remains on the
  Blocks step (confirmation only required when it would empty the
  list at submit time).

### Requirement: Sequential Dispatch With Per-Step Reconciliation
On submit (Review step), the wizard SHALL dispatch the season
create, then per block the block create and its episode creates,
through the existing repositories with the established
optimistic-after-2xx and bounded-retry reconciliation per command
(step progress visible). All ids in command payloads SHALL source
exclusively from command responses and the wizard's draft state
(CQRS boundary rule). Partial failure SHALL stop further dispatch,
report the created-so-far summary, and offer an in-session retry of
the failed step's remaining commands — no background queue, no
offline persistence.

#### Scenario: Happy path dispatch
- **WHEN** the user confirms the Review step for 2 blocks × 4
  episodes.
- **THEN** the season, blocks, and episodes are created via the
  existing commands; the wizard advances to the Completion screen
  listing the created structure.

#### Scenario: Partial failure
- **WHEN** a block create fails mid-sequence (conflict/transport).
- **THEN** the wizard stops dispatching, shows the created-so-far
  summary with the localized problem-code copy, and offers a retry
  of the remaining commands in-session.

#### Scenario: Command ids never come from projections
- **WHEN** block and episode commands are dispatched.
- **THEN** their `season_id`/`block_id` come from the create
  responses (or draft state), never from a second projection
  lookup.

### Requirement: Destructive Abort With Confirmation
Leaving the wizard (back-out, app exit, or explicit cancel) SHALL
discard all draft state after an explicit confirmation dialog that
names what will be lost. No draft is written to Drift or any other
persistent store pre-submit (team decision 3: no resume). Once
dispatch has started, confirm-cancel is disallowed in favor of the
partial-failure/completion paths.

#### Scenario: Cancel with drafts entered
- **WHEN** the user taps cancel after entering drafts and confirms
  the discard dialog.
- **THEN** the wizard closes, nothing was created or persisted, and
  reopening starts fresh.

#### Scenario: Abort during dispatch
- **WHEN** dispatch is in flight.
- **THEN** the cancel affordance is disabled until the sequence
  settles (completion or partial-failure state).

### Requirement: Conditional AI-Import Completion CTA
The Completion screen SHALL offer "AI-Import starten" only when an
AI provider/model configuration exists (checked client-side via
the existing ai-config read before render). Without configuration,
an info card SHALL render explaining the prerequisite with an
action to the AI configuration screen (team decision 6). The
check itself performs no protected network call beyond the existing
config read path with its own AUTHZ-GATE discipline.

#### Scenario: Configured provider
- **WHEN** the user completes the wizard with an AI configuration
  present.
- **THEN** the completion CTA "AI-Import starten" renders and links
  to the import submission flow for the created season.

#### Scenario: No configuration
- **WHEN** no AI configuration exists.
- **THEN** the completion screen renders the prerequisite info card
  with an action to the AI configuration screen instead of the
  import CTA.

### Requirement: Wizard Entry Points
The wizard SHALL be reachable from the Season tab's guided empty
state ("Season-Setup starten") and from the create flow entry (as
the guided path alongside the existing quick-create sheet). The
wizard runs inside the shell's tab stack (no routing package).

#### Scenario: Entry from empty state
- **WHEN** an authenticated user with zero seasons taps the empty
  state's setup CTA.
- **THEN** the wizard opens as a full-screen step flow within the
  Season tab's navigator.

#### Scenario: Auth gate
- **WHEN** the wizard's command steps run.
- **THEN** each dispatch follows the existing AUTHZ-GATE comments
  and session conditions of the underlying create commands.
