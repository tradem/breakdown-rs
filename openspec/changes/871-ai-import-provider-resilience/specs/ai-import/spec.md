<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

# ai-import

## ADDED Requirements

### Requirement: A provider breaker holds a job instead of spending its retry budget

The system SHALL maintain a **durable** provider-health breaker keyed on
`(provider, model)` — the pair the job's resolved AI configuration names — in
`ai_import.provider_health`, and SHALL consult it on **every** claim path
(`claim_next`, `claim_next_kind`, the two reconciling variants) so a job whose
endpoint is known to be failing is not claimed at all.

The breaker SHALL open only on **retryable provider failures** (the
`ServiceUnavailable` shape carrying `ai-import.llm-provider-unavailable`) and
SHALL reach a count of `AI_IMPORT_BREAKER_FAILURE_THRESHOLD` (default 3)
consecutive such failures before opening. A permanent provider failure
(`dependency.auth-failed` class — revoked key, entitlement, bad model) SHALL
NEVER open it, and neither SHALL a non-provider `domain.service-unavailable`
failure (mapping DB, pricing read model, payload storage, catalog parse).

A job that hits an open breaker — before the claim or at a chunk boundary during
a run — SHALL be **held**, not failed:

- `retries` SHALL NOT be incremented;
- NO `ai_import.ai_import_job_attempt` row SHALL be appended;
- `status` SHALL stay `failed`;
- `next_attempt_at` SHALL be set to the breaker's probe time;
- `progress` SHALL be preserved;
- the additive `AiImportJob.provider_hold` field SHALL be populated with
  `provider`, `model`, `reason_code`, `state`, `until`, `hold_deadline` and
  `chunks_done`.

The hold SHALL expire: after `AI_IMPORT_MAX_PROVIDER_HOLD_SECS` (default 6 h) the
job SHALL transition to `dead_letter` with the provider narrative, with `retries`
still unchanged and exactly one attempt row recorded.

#### Scenario: Three consecutive provider failures hold the queue instead of burning the budget
- **WHEN** three consecutive chunk calls of one `(provider, model)` fail with
  `ai-import.llm-provider-unavailable`
- **THEN** the breaker opens and every later claim of a job on that pair is
  rejected by the SQL predicate
- **AND** each affected running job is `mark_held` with an unchanged `retries`, no
  new attempt row, and `provider_hold.until` equal to the breaker's probe time

#### Scenario: A permanent provider failure never opens the breaker
- **WHEN** a chunk call fails with a revoked-key / entitlement error
- **THEN** the job takes the existing permanent-failure path
  (`mark_failed(..., retryable = false)`)
- **AND** `ai_import.provider_health.consecutive_failures` for that pair is
  unchanged

#### Scenario: A running job stops before the next billable call
- **WHEN** the breaker opens while a job is at chunk 25 of 42
- **THEN** the worker stops at the chunk boundary before issuing chunk 26's call
- **AND** the job is held with `chunks_done = 25` and no retry consumed

#### Scenario: A held job expires into the provider narrative
- **WHEN** a job has been held for `AI_IMPORT_MAX_PROVIDER_HOLD_SECS`
- **THEN** it transitions to `dead_letter` naming the provider
- **AND** `retries` is unchanged and exactly one attempt row is recorded

### Requirement: Breaker recovery is half-open, single-prober and flap-bounded

The breaker SHALL recover through a `half_open` state: at its probe time exactly
one worker SHALL be admitted to probe (a compare-and-set on the probe owner plus a
probe lease, so a crashed prober cannot wedge the state), and the breaker SHALL
close only on a successful probe or a successful paid call — never on elapsed
time alone.

The probe SHALL be the existing cheap model-catalog read (`GET {base}/models`),
authenticated with the credential of the job whose observation opened the
breaker. No paid completion SHALL be spent to learn that an endpoint recovered.

The minimum open duration SHALL escalate with the flap count
(`min(BASE_OPEN · 2^flaps, MAX_OPEN)`, 60 s base, 30 min cap), and a flap SHALL
only be counted when the breaker re-opens inside `STABLE_WINDOW` (5 min) after
closing, so a provider that answers once and fails again cannot loop the queue
through open/closed at a fixed rate.

#### Scenario: Recovery closes the breaker and the held job completes
- **WHEN** the probe at `retry_at` succeeds
- **THEN** the breaker returns to `closed`, the failed-attempt counter resets, and
  the held job is claimable at its next `next_attempt_at`
- **AND** the resumed attempt continues at the job's stored chunk cursor

#### Scenario: A flapping provider is damped, not looped
- **WHEN** a provider closes the breaker and re-opens it again within
  `STABLE_WINDOW`, repeatedly
- **THEN** each re-open doubles the minimum open duration up to `MAX_OPEN`
- **AND** the probe frequency decays instead of oscillating

### Requirement: A retried attempt resumes at the first uncompleted chunk

Every completed chunk's **parsed result** and its call usage SHALL be persisted in
`ai_import.ai_import_job_chunk` keyed `(job_id, chunk_index)` (overwrite on
replay), so a paid chunk is never paid for twice by a retried attempt and the loss
of a worker between two chunks does not discard the chunks already extracted.

The resume cursor SHALL be **derived** (`max(chunk_index) + 1`), never a stored
column, so a lost write can never leave the cursor ahead of or behind the rows.
`progress.chunk` SHALL keep its meaning (1-based index of the last completed chunk
of the current attempt) and the additive `AiImportProgress.resumed_from` SHALL
name the first uncompleted chunk (`n` means chunks `1..=n` are stored).

#### Scenario: A run that died at chunk 25 of 42 resumes at chunk 26
- **WHEN** a job whose chunk rows cover `1..=25` is re-claimed
- **THEN** the attempt issues no call for chunks 1–25
- **AND** its first extraction frame reports `resumed_from = 25` and
  `chunk = 25`, and the provider is first asked for chunk 26

#### Scenario: A crash between chunks never yields a preview with a hole
- **WHEN** the worker is killed after persisting chunk 25 and before chunk 26
- **THEN** the job's stored chunks are exactly `1..=25`
- **AND** no preview exists until a later attempt has produced every chunk

#### Scenario: A chunk re-run repairs a lost write instead of duplicating it
- **WHEN** a chunk's result is re-produced after a lost insert
- **THEN** the row for that `(job_id, chunk_index)` is overwritten
- **AND** the chunk is counted once in the job's usage

### Requirement: Resume is invalidated by any change that determines the output

The job SHALL carry an extraction fingerprint over everything the system controls
that determined the extracted result — document digest, `provider`, `model`, the
hash of the effective prompt (stored prompt when configured, else the deployment
default) and the chunker version. When a re-claimed attempt would produce a
different fingerprint than the one the stored chunks were produced under, the
system SHALL delete the job's stored chunk rows, record the new fingerprint, log
the invalidation with the component(s) that changed (log-only; never on the wire),
and restart extraction at chunk 0.

A resume SHALL therefore never mix chunks produced by two different models or
prompts.

#### Scenario: A model change restarts instead of resuming
- **WHEN** the user's active AI configuration changes model between two attempts
  of the same job, and chunk rows `1..=25` exist
- **THEN** the rows are deleted, the attempt starts at chunk 0, and the
  invalidation is logged naming the model
- **AND** the attempt's progress publishes no `resumed_from`

#### Scenario: An unchanged configuration resumes as before
- **WHEN** provider, model, the effective prompt and the document digest are
  unchanged
- **THEN** the fingerprint matches and the attempt resumes at `max + 1`

### Requirement: The cost snapshot counts every paid call exactly once

Each stored chunk SHALL carry its own call usage, and the job's immutable cost
snapshot (`CostBreakdown`) SHALL be assembled from the usage of **all** stored
chunks plus the attempt-level calls, so an import that took three attempts is
visibly more expensive than a clean one and no paid call is counted twice.

A call whose result never persisted SHALL NOT be counted; that residual spend is
bounded by one chunk per interruption and SHALL be documented as the one
uncounted case rather than estimated or guessed.

#### Scenario: A retried import costs more than a clean one
- **WHEN** an import resumed at chunk 26 and paid for chunks 1–25 on an earlier
  attempt
- **THEN** the completion snapshot's token/energy components include all 42
  chunks
- **AND** each chunk appears exactly once

#### Scenario: A re-run chunk does not double count
- **WHEN** one chunk was produced twice and its row was overwritten
- **THEN** its usage is counted once

### Requirement: Provider-breaker state is operable from a durable signal

Every breaker transition SHALL be logged with the greppable marker
`#871 provider breaker` and the fields `provider`, `model`, `state`,
`consecutive_failures`, `retry_at` and `flap_count`, and the durable row plus a
documented runbook query SHALL answer — without reading job rows one by one:

- is the breaker open, for which pair, and since when;
- which jobs are held for it right now;
- how far a job under investigation has resumed.

The public `GET /v1/health` route SHALL NOT be extended with a provider check: it
is unauthenticated with a bounded per-check timeout and a provider probe requires
a vaulted credential.

#### Scenario: An operator answers the three questions from the runbook
- **WHEN** operators suspect a provider outage
- **THEN** the runbook query lists open breakers with `opened_at`/`retry_at` and
  the held jobs grouped by `(provider, model)`
- **AND** the same facts are recoverable from the `#871 provider breaker` log
  marker

## MODIFIED Requirements

### Requirement: Resilience and bounded cost

The system SHALL bound LLM cost exposure via: a per-job request cap (max chunks;
exceeded → `Failed`, no retry), a per-user in-flight concurrency cap, a
`(provider, model)` provider breaker that holds work instead of paying to
re-discover an outage, chunk-level resume so a retried attempt does not re-buy a
completed chunk, and an `AiImportBounds` config carrying compile-time and
env-guarded ceilings (`max_chunks_per_script`, `max_tokens_per_req`,
`max_concurrent_jobs_global`).

The two retry layers SHALL be separately bounded: `AI_IMPORT_MAX_RETRIES`
(job-level, default 5, unchanged) and `AI_IMPORT_MAX_ATTEMPT_RETRIES`
(in-attempt per chunk, default 2), so one chunk cannot be paid for
`(1 + attempt_retries) × job_retries` times; a compile-time invariant SHALL
guarantee that the in-attempt budget can actually reach the breaker threshold.
A held job SHALL release its concurrency permit (the hold ends the attempt),
while an in-attempt retry keeps it for an analytically bounded window of
`(1 + max_attempt_retries) × request_timeout_secs`, and a retry SHALL short-
circuit instead of sleeping when the breaker is open.

Dollar/token spend SHALL still be enforced at the provider side; local caps are
defense in depth.

#### Scenario: Per-job request cap stops a runaway import
- **WHEN** a script import would exceed `max_chunks_per_script`
- **THEN** the job transitions to `Failed`
- **AND** no further LLM calls are made for that job

#### Scenario: The two retry layers no longer multiply
- **WHEN** a chunk fails with a transient provider error
- **THEN** it is retried at most `AI_IMPORT_MAX_ATTEMPT_RETRIES` times in-attempt
- **AND** the job-level budget is charged only by attempts that actually ran

#### Scenario: An open breaker costs neither a call nor a sleep
- **WHEN** the in-attempt retry loop finds the breaker open before its next
  attempt
- **THEN** it stops immediately without issuing a call and without sleeping the
  backoff

#### Scenario: A waiting job occupies no capacity
- **WHEN** a job is held for an open breaker
- **THEN** its concurrency permit is released with the attempt
- **AND** another job of the same user may use the freed capacity

### Requirement: Owner-fenced job progress with stage and episode visibility

The operational `AiImportJob` record SHALL carry an optional `progress` payload
(`AiImportProgress`: `stage`, `chunk`, `chunks_total`, `episodes_seen`,
`resumed_from`) persisted in `ai_import.ai_import_job.progress` (`JSONB`) and
exposed on `GET /v1/ai-import/jobs/{id}`, `GET /v1/ai-import/jobs`, and
`GET /v1/ai-import/jobs/{id}/events`. Progress writes SHALL be executed via an
owner-fenced `AiImportQueue::mark_progress` method
(`WHERE id = $1 AND status = 'running' AND claimed_by = $2`) and SHALL be
throttled to stage transitions (`extracting_text`, `extracting`, `merging`,
`storing_preview`) and completed chunks (`1..=chunks_total`), NEVER per generated
LLM token. The `episodes_seen` list SHALL be populated at zero extra LLM token
cost from the deterministic `Ep.:` marker scan and extracted per-chunk
`DraftEpisode` metadata in first-seen order, deduplicated.

Re-claiming a job after a retryable failure SHALL reset `progress` to `null` so
stale progress from an earlier attempt is never served — and an attempt that
resumes from stored chunks SHALL, once it publishes, report the resume point
(`resumed_from` = number of stored chunks, first frame `chunk = resumed_from`)
instead of restarting its counter at 0, so neither the progress bar nor the
client-side remaining-time estimate (#762) pretends the resumed chunks are still
to be paid for.

#### Scenario: Script worker publishes throttled per-chunk progress and episodes seen
- **WHEN** a script import job with 12 scene chunks processes chunks 1 through 4
  spanning markers `Ep.: 3` and `Ep.: 4`
- **THEN** the worker calls `mark_progress` once after chunking and once after
  each completed chunk (never per LLM token)
- **AND** after chunk 4 the persisted `job.progress` carries
  `stage = "extracting"`, `chunk = 4`, `chunks_total = 12`, and
  `episodes_seen = ["Ep. 3", "Ep. 4"]`

#### Scenario: Displaced worker cannot overwrite progress
- **WHEN** a worker whose claim lease expired calls `mark_progress` after
  another worker has reclaimed the job
- **THEN** `mark_progress` affects zero rows and returns `DomainError::Conflict`
- **AND** the new owner's `progress` state remains intact

#### Scenario: Retry reclaim clears stale progress from a prior attempt
- **WHEN** a retryable `failed` job with non-null `progress` from attempt 1 is
  claimed for attempt 2
- **THEN** the claim transition resets `progress` to `null` before attempt 2
  begins processing

#### Scenario: A resumed attempt reports where it resumed
- **WHEN** attempt 2 of a 42-chunk job resumes with 25 stored chunks
- **THEN** its first extraction frame carries `resumed_from = 25` and
  `chunk = 25`
- **AND** a pre-#871 client that ignores the field still shows a coherent
  `chunk`/`chunks_total` pair
