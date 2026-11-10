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
a run — SHALL be **held**, not failed, and **every** owed job of an open pair SHALL
carry a hold regardless of how it reached that state: opening a breaker SHALL
materialize the hold on the runnable jobs of that pair in one statement (no claim,
no owner, no provider call), a running job SHALL be held by its owner, and a
periodic claim-free sweep SHALL hold the remainder — a job **enqueued while the
breaker is already open** and a `failed` job whose retry becomes due **after** the
opening transition. Without the sweep those two are neither visible nor
expirable, because the expiry precondition is the hold itself. In every case:

- `retries` SHALL NOT be incremented;
- NO `ai_import.ai_import_job_attempt` row SHALL be appended;
- `status` SHALL stay `failed`;
- `next_attempt_at` SHALL be set to the breaker's probe time;
- `progress` SHALL be preserved;
- the additive `AiImportJob.provider_hold` field SHALL be populated with
  `provider`, `model`, `reason_code`, `state`, `until`, `hold_deadline` and
  `chunks_done`.

The hold SHALL expire without requiring a claim: a periodic claim-free sweeper
SHALL dead-letter a held job whose own `hold_deadline` has passed, because the
claim predicate keeps such a job unclaimable and an owner-fenced write could never
reach it. On expiry the job SHALL transition to `dead_letter` with the provider
narrative, with `retries` still unchanged and exactly one attempt row recorded.

The deadline SHALL be a **series** clock that survives short recoveries: it is
derived from a durable series-start column that a breaker close does NOT clear, so
a provider that flaps closed → open every few minutes cannot keep resetting the
deadline and thereby prevent the expiry. The series ends when the job is claimed
(it actually ran), after a sustained recovery, or on any terminal write.

`provider_hold` SHALL be kept on the expiry write with `state = expired` — the
durable marker that separates "the provider never came back" from "the retry budget
is spent" — and that write is the **only** terminal path that does not clear the
field. Every other terminal transition (success, `payload_unavailable`, ordinary
failure/dead-letter) clears it as before.

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

#### Scenario: A queued job is held without ever being claimed
- **WHEN** the breaker for a pair opens while three jobs of that pair are queued
  (`pending`) and none is running
- **THEN** the opening transition holds all three (status `failed`,
  `next_attempt_at` = probe time, `provider_hold` populated)
- **AND** no provider call is issued and no retry is charged

#### Scenario: A job enqueued after the breaker opened is held, not stranded
- **WHEN** a job is enqueued for a pair whose breaker is already `open`
- **AND** its retry, or a job whose `next_attempt_at` fell due after the opening
  transition, is excluded by the claim predicate
- **THEN** the sweep writes the same hold on it (status `failed`,
  `next_attempt_at` = probe time, `provider_hold` populated, series clock set)
- **AND** the job is therefore both visible and expirable, and no provider call was
  made to discover that

#### Scenario: A held job expires into the provider narrative
- **WHEN** a job has been held past its `hold_deadline`
- **THEN** the claim-free sweeper transitions it to `dead_letter` naming the
  provider
- **AND** `retries` is unchanged and exactly one attempt row is recorded

### Requirement: Breaker recovery is half-open, single-prober and flap-bounded

The breaker SHALL recover through a `half_open` state: at its probe time exactly
one probe SHALL be admitted (a compare-and-set on the probe owner plus a probe
lease, so a crashed prober cannot wedge the state), and the breaker SHALL close
only on a successful probe or a successful paid call — never on elapsed time
alone. **No claim SHALL be admitted while the breaker is not `closed`**: the probe
is a task of its own, not a claimed job, so a due probe cannot turn into a queue
drain of paid calls.

The probe SHALL be a **reachability** read of the same endpoint the jobs use, and it
SHALL judge reachability only:

- the hosted path uses the existing cheap model-catalog read (`GET {base}/models`);
- the **Ollama** path SHALL probe **unauthenticated** (the curated `/api/tags`
  endpoint through the local-only redirect policy), because Ollama has no API key at
  all and the catalog client rejects an empty key while always sending a bearer
  token — which would also leak a credential to a plain-HTTP local origin
  (CWE-319). An Ollama breaker MUST be able to close.

A probe result SHALL NEVER retire, fail or otherwise terminalize a job: it is a
verdict about the endpoint. A 2xx closes the breaker; a transport error, timeout,
429 or 5xx keeps it open and advances its probe time (flap rule applies); a 401 or
403 **closes** it as well — the endpoint answered, and a catalog denial does not
establish that the credential cannot run a completion (a restricted key may allow
chat without model listing, and a key may be replaced while the request is in
flight). A job whose own credential is unusable is terminalized by its **own**
attempt through the existing permanent path, never by a probe.

The donor job's identity SHALL be captured with the credential selection (job id,
user id, document kind) and used for the log line and candidate rotation, never
re-derived later: re-selecting "a job of that user" would pick a different job as
soon as the first one expires.

The probe SHALL run in **three short steps** — commit the lease CAS, perform the
request outside any transaction, then commit the fenced result — so a hung request
cannot hold the breaker row lock and thereby block the lease takeover it depends
on.

Every probe **result** SHALL be fenced to the **lease that produced it**, not to the
owner: a fresh lease token per probe attempt, matched by both result writes
together with the `half_open` state, so neither a probe that outlives its lease nor
the same owner reacquiring it can close or re-open a state it no longer owns.

A rejected-credential probe SHALL NOT increment the flap count.

No paid completion SHALL be spent to learn that an endpoint recovered.

The minimum open duration SHALL escalate with the flap count
(`min(BASE_OPEN · 2^flaps, MAX_OPEN)`, 60 s base, 30 min cap), and a flap SHALL
only be counted when the breaker re-opens inside `STABLE_WINDOW` (5 min) after
closing, so a provider that answers once and fails again cannot loop the queue
through open/closed at a fixed rate.

#### Scenario: A due probe does not become a queue drain
- **WHEN** a breaker reaches its probe time with five jobs of that pair queued
- **THEN** only the single probe is admitted (one CAS winner) and no job is
  claimed
- **AND** the jobs stay held until the probe closes the breaker

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

#### Scenario: A dead probe credential does not pin the breaker

- **WHEN** the donor job's credential is revoked and the probe answers 401
- **THEN** the breaker closes (the endpoint answered) and the flap count is
  unchanged, and **no** job is terminalized by the probe
- **AND** that job's own attempt fails with `dependency.auth-failed` through the
  existing permanent path and terminalizes itself

#### Scenario: A catalog-only denial does not kill a job

- **WHEN** the probe answers 403 because the key may run chat completions but may
  not list models
- **THEN** the breaker closes and the outcome is logged, and the job stays queued
- **AND** the job can complete once the hold is released

#### Scenario: An Ollama breaker can recover

- **WHEN** the provider is Ollama
- **THEN** the probe is issued unauthenticated (no vault read, no bearer token) and
  a 2xx closes the breaker
- **AND** the plain-HTTP curated origin never receives a credential

#### Scenario: The probe never holds the breaker lock across the request

- **WHEN** the catalog request hangs until its timeout
- **THEN** the lease CAS is already committed and the breaker row is unlocked
- **AND** another tick may take over the expired lease, and the hung probe's late
  result is discarded because its lease token no longer matches

#### Scenario: An expired job is never a probe credential donor

- **WHEN** the oldest job of the pair carries the retained expiry marker
  (`provider_hold.state = expired`)
- **THEN** the probe selects the next active held job instead, and never rewrites
  the expired marker

#### Scenario: A stale probe result is discarded

- **WHEN** a probe returns after its lease expired and another probe lease now owns
  the state
- **THEN** its result rewrites nothing (zero rows) and the current probe's state
  stands

#### Scenario: The same owner reacquiring the lease is still fenced

- **WHEN** a probe task instance abandons a result and later acquires a new probe
  lease for the same pair
- **THEN** the abandoned result matches no lease token and rewrites nothing, for a
  successful and for a failed probe alike

### Requirement: A retried attempt resumes at the first uncompleted chunk

Every completed chunk's **parsed result** and its call usage SHALL be persisted in
`ai_import.ai_import_job_chunk` keyed `(job_id, chunk_index)` (overwrite on
replay), so a paid chunk is never paid for twice by a retried attempt and the loss
of a worker between two chunks does not discard the chunks already extracted.

The resume cursor SHALL be **derived**, never a stored column: it is the length of
the **contiguous stored prefix** starting at chunk 0 (the first index that is
missing), so a lost write, a hole or a stale cursor can neither skip a chunk nor
silently shorten the work — a row beyond a hole SHALL be discarded as unusable
rather than resumed past. `progress.chunk` SHALL keep its meaning (1-based index of
the last completed chunk of the current attempt) and the additive
`AiImportProgress.resumed_from` SHALL name the number of contiguous stored chunks
(`n` means chunks `1..=n` are stored).

Every chunk write SHALL be fenced to the claim that produced it (job id, owning
worker, extraction fingerprint) **by a row lock, not a predicate alone**: the write
takes the job row `FOR UPDATE` in its own transaction, verifies owner and
fingerprint against the locked row, and holds the lock through the chunk insert;
the invalidation path (fingerprint rewrite + chunk-row delete) takes the same lock
on the same row in the same order, in one transaction. Under READ COMMITTED a bare
`INSERT … SELECT … WHERE …` can read the old owner and commit after another worker
has reclaimed and invalidated the job, so a worker that lost its claim during an
in-flight call SHALL NOT be able to insert a result produced under the old
configuration into a chunk set that has since been invalidated.

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

#### Scenario: A hole in the stored chunk set is not resumed past
- **WHEN** stored indices are `0, 1, 3`
- **THEN** the resume cursor is `2`, and the row for chunk `3` is discarded
- **AND** extraction resumes at chunk `2`, so no resumed preview omits a chunk

#### Scenario: A worker that lost its claim cannot write a chunk
- **WHEN** a worker's claim lapsed during an in-flight call and the job was
  reclaimed with a different extraction fingerprint
- **THEN** its chunk write affects zero rows and returns `DomainError::Conflict`
- **AND** the new owner's chunk set is unchanged

#### Scenario: The write fence survives a concurrent invalidation
- **WHEN** two sessions race — one writing a chunk under an old fingerprint, one
  reclaiming the job and rewriting the fingerprint — in either submission order
- **THEN** the outcome is serialized by the job-row lock: either the chunk lands
  before the fingerprint changes, or it is refused
- **AND** a chunk produced under the old configuration is never present in the new
  set

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
- **THEN** the fingerprint matches and the attempt resumes at the first missing
  chunk

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
`(1 + attempt_retries) × job_retries` times. The breaker's failure counter is per
`(provider, model)` across all jobs, chunks and replicas, so the two knobs do not
have to line up for the breaker ever to open — a lower in-attempt budget only
makes it open more slowly, and a configured mismatch SHALL be logged rather than
rejected. A held job SHALL release its concurrency permit (the hold ends the
attempt), while an in-attempt retry keeps it for an analytically bounded window
that includes the **backoff sleeps** as well as the request timeouts —
`(1 + max_attempt_retries) × request_timeout_secs + max_attempt_retries × 30 s`,
7 min at the defaults — and a retry SHALL short-circuit instead of sleeping when
the breaker is open.

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

#### Scenario: A breaker opened during the backoff stops the next call
- **WHEN** another worker opens the breaker while the loop sleeps its backoff
- **THEN** the check at the top of the next iteration sees it and the retry issues
  no call
- **AND** the guard is consulted before every attempt, not only before a sleep

#### Scenario: A parse retry inside one attempt is guarded too
- **WHEN** the first billed request of an attempt returns a truncated response and
  the client is about to re-request at a doubled budget, while the breaker has been
  opened by another worker
- **THEN** that second request is not issued and the attempt ends on the hold path
- **AND** the internal breaker sentinel is never serialized as a wire error

#### Scenario: The permit bound counts the waits, not only the calls
- **WHEN** the in-attempt worst case is computed from `max_attempt_retries = 2`,
  `request_timeout_secs = 120`, the 30 s backoff cap and the client-internal
  truncation retries (`MAX_TRUNCATION_RETRIES = 2`, Ollama up to 3)
- **THEN** the bound is `3 × 3 × 120 s + 2 × 30 s = 19 min` on the hosted path and
  `3 × 4 × 120 s + 2 × 30 s = 25 min` on Ollama
- **AND** a fake transport counting requests asserts both, instead of sleeping them

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
