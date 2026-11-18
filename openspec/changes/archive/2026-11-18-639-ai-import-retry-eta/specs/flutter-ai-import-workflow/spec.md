<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (neuralwatt) -->

# flutter-ai-import-workflow Delta (639-ai-import-retry-eta)

## MODIFIED Requirements

### Requirement: Job Status With Terminal Error States
The job status screen SHALL watch the job with bounded, foreground-
only refetching (no background polling/wake-ups) and render every
status honestly: pending/running with indeterminate progress (no
fabricated percentages), retryable `failed` with `retries/max_retries`,
a live localized time until the next planned attempt derived from
`next_attempt_at`, and the reason the prior attempt(s) failed keyed on the
attempt's stable problem `code`; and terminal
`dead_letter`/`payload_unavailable` as error cards whose primary copy is
keyed on the status with the attempt's code-keyed reason and `last_error`
as secondary text only. A "cancel" affordance SHALL NOT exist (no server
route); the user may only close/leave, and the copy SHALL say so. When
`next_attempt_at` is absent the screen SHALL say a retry is scheduled
without inventing a time; copy SHALL NEVER be interpolated from the
backend `detail`/`error_summary`.

#### Scenario: Processing latency
- **WHEN** a job stays in pending/running across watch ticks.
- **THEN** the screen shows the indeterminate progress affordance and
  remains interactive (no UI-thread block); leaving the screen stops
  the watch and returning re-arms it.

#### Scenario: Retryable failure shows a live ETA
- **WHEN** a retryable `failed` job carries `next_attempt_at` in the
  future.
- **THEN** the retryable card renders a localized "next retry in …"
  that updates as time passes, alongside the retry budget.

#### Scenario: Retryable failure without an ETA degrades honestly
- **WHEN** a retryable `failed` job has no `next_attempt_at`.
- **THEN** the card says a retry is scheduled and shows no countdown —
  no fabricated time.

#### Scenario: Retryable failure explains the prior attempt
- **WHEN** a retryable `failed` job carries attempt history.
- **THEN** the reason of the newest attempt is rendered on the retryable
  card, localized from the ARB catalog keyed on the attempt's problem
  `code`; an absent or unrecognized `code` renders the generic localized
  reason, never the raw backend summary as identity.

#### Scenario: Terminal processing error
- **WHEN** the job reaches `dead_letter` or `payload_unavailable`.
- **THEN** the terminal error card renders with status-keyed primary
  copy and the `last_error` string as secondary detail; the watch ends.
