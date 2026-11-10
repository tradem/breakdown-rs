<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

# flutter-ai-import-workflow

## ADDED Requirements

### Requirement: A held job renders why it is waiting, not that it failed

The client SHALL render the additive `AiImportJob.provider_hold` state as a
**waiting** state that extends the #822 degraded-provider banner rather than
contradicting it. The rendered copy SHALL name:

- the provider (never "a service"),
- the next probe time (`until`, rendered through the existing live
  "next retry in …" affordance — never a second countdown),
- the hold's absolute deadline (`hold_deadline`), and
- that waiting is the correct action: no retry of the import is consumed while
  held.

The client SHALL NOT render the held state as a failure, SHALL NOT invent a new
job status, and SHALL NOT hide the waiting state behind the per-attempt list. A
job without `provider_hold` SHALL render exactly as today, and a client that does
not know the field SHALL keep working (it is additive and optional on the wire).

German copy (shipped template locale, quoted as it appears):

- banner: `Anbieter nicht erreichbar · wartet bis {time} · spätestens {deadline}`
- second line: `Kein Versuch wird verbraucht — der Import läuft nach der Pause
  weiter.`

#### Scenario: A held job waits visibly

- **WHEN** a `failed` job carries `provider_hold` with `state = open`,
  `until` and `hold_deadline`
- **THEN** the job-status screen renders the waiting banner naming the provider,
  the probe time and the deadline
- **AND** the jobs list row shows the compact form of the same state
- **AND** neither surface presents the job as permanently failed

#### Scenario: A job without a hold is unchanged

- **WHEN** a `failed` job carries no `provider_hold`
- **THEN** it renders exactly as before this change

## MODIFIED Requirements

### Requirement: Job Status With Terminal Error States

The job-status surface SHALL distinguish, from the job's own persisted state, the
following conditions and SHALL never promise a retry the state cannot deliver:
`pending`, `running` (with stage and per-chunk progress), retryable `failed`,
terminal `dead_letter`, non-resumable `payload_unavailable`, the aggregated
degraded-provider state, and — since issue #871 — a job **held** for an open
provider breaker.

For a held job the surface SHALL state that the import waits for the provider, the
time of the next probe and the hold's deadline, and that no retry budget is being
consumed. Once the hold expires into `dead_letter`, the surface SHALL render the
terminal provider narrative (retry budget spent because the provider never
recovered), never "the next attempt may succeed".

For a running job whose progress carries `resumed_from > 0`, the surface SHALL
say where the attempt resumed (German: `Fortsetzung ab Szene {n} von {total}`)
instead of presenting the resumed chunks as freshly processed. The remaining-time
estimate SHALL be derived from the work done **in this attempt**
(`chunk − resumed_from`) against the attempt's `started_at`, so a resumed attempt
does not claim to have processed 25 chunks in one second.

#### Scenario: Running job shows stage and progress

- **WHEN** a job is `running` with `progress.stage = extracting` and
  `chunk = 4` of `chunks_total = 12`
- **THEN** the surface shows the extraction stage and a 4/12 progress indicator

#### Scenario: Retryable failure shows the next attempt

- **WHEN** a `failed` job carries `next_attempt_at`
- **THEN** the surface shows the localized retryable narrative and the live
  "next retry in …" affordance

#### Scenario: A resumed attempt reports honestly

- **WHEN** a running job's progress carries `resumed_from = 25` and `chunk = 25`
  of `chunks_total = 42`
- **THEN** the surface states that the attempt resumes at scene 26 and still shows
  25/42 completed
- **AND** the remaining-time estimate is not derived from 25 chunks processed in
  the attempt's first second

#### Scenario: An expired hold reads as terminal, not as retryable

- **WHEN** a job that was held is now `dead_letter` after the hold expired
- **THEN** the surface states that the provider did not recover within the
  deadline
- **AND** it does not promise that the next attempt may succeed
