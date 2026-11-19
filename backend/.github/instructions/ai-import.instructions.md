---
description: AI import - configuration, concurrency permits, payload storage, GC and restart recovery.
applyTo:
  - "crates/*/src/ai/**"
  - "crates/integration-tests/tests/ai*"
  - "config/default_ai_prompts.toml"
---

<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3 (neuralwatt) -->
<!-- Co-authored-by: space-bunny-free (opencode-go) -->

# AI import (`add-ai-script-and-schedule-import`)

#### AI import (`add-ai-script-and-schedule-import`)

- `AI_IMPORT_ENABLED` – enable AI import routes/workers (default: `false`; accepted values: `true`, `1`, `yes`).
- `AI_IMPORT_MAX_CHUNKS_PER_SCRIPT` – maximum script scene chunks per job (default: `128`; bounded to `1..=10000`).
- `AI_IMPORT_MAX_TOKENS_PER_REQ` – maximum output tokens per LLM request (default: `8192`; bounded to `1..=1000000`).
- `AI_IMPORT_MAX_CONCURRENT_JOBS_GLOBAL` – global in-flight job ceiling (default: `16`).
- `AI_IMPORT_MAX_CONCURRENT_JOBS_PER_USER` – per-user in-flight job ceiling (default: `2`).
- `AI_IMPORT_MAX_DOCUMENT_BYTES` – maximum source document size (default: `20971520`).
- `AI_IMPORT_REQUEST_TIMEOUT_SECS` – provider request timeout (default: `120`).
- `AI_IMPORT_MAX_RETRIES` – **job-level** retries before dead-lettering (default: `5`).
- `AI_IMPORT_MAX_ATTEMPT_RETRIES` – **in-attempt** retries of one chunk's provider call (default: `2`, bounded `0..=10`). Since issue #871 this is a *second* knob: one knob allowed `5 × 5 = 25` paid calls for a single chunk before anything surfaced, each holding a concurrency permit for up to `AI_IMPORT_REQUEST_TIMEOUT_SECS`. `1 + 2 = 3` attempts per chunk is enough to tell a blip from an outage. The analytic worst case of one attempt across **both** nested layers is `(1 + max_attempt_retries) × (1 + inner_retries) × request_timeout_secs + max_attempt_retries × max(30 s, MAX_IN_ATTEMPT_HINT_SECS)` = **22 min** hosted (`inner = 2`) / **28 min** Ollama (`inner ≤ 3`), because the clients re-request a truncated/malformed answer inside one attempt and, since issue #926, a provider-requested wait can raise each in-attempt pause from 30 s to 120 s (see "Provider retry hints").
- `AI_IMPORT_BREAKER_FAILURE_THRESHOLD` – consecutive retryable provider failures for one `(provider, model)` pair that open the breaker (default: `3`, bounded `1..=10`). Counted per **pair across all jobs, chunks and replicas**. A threshold above `1 + AI_IMPORT_MAX_ATTEMPT_RETRIES` is accepted but logged at startup: the breaker still opens, just more slowly, because one chunk then contributes one failure instead of up to three.
- `AI_IMPORT_BREAKER_ENABLED` – kill switch for the breaker (default: `true`; accepted spellings as `AI_IMPORT_ENABLED`). `false` restores the pre-#871 behaviour exactly.
- `AI_IMPORT_MAX_PROVIDER_HOLD_SECS` – how long one **hold series** may last before the job dead-letters with the provider narrative (default: `21600` = 6 h, bounded `60..=604800`). Measured from the first hold of the series, so a flapping provider cannot reset the budget one probe at a time.
- `AI_IMPORT_PROVIDER_SWEEP_ENABLED` – enable the provider watch (default: `true`).
- `AI_IMPORT_PROVIDER_SWEEP_INTERVAL_SECS` – provider-watch cadence in seconds (default: `60`, bounded `5..=3600`).
- `AI_IMPORT_LEASE_SECS` – worker claim lease in seconds (default: `900`). An out-of-range number is clamped to `30..=86400`; only absent/unparsable values fall back to the default. A claim records `worker_id` + `lease_expires_at`; once the lease expires another worker may reclaim the `running` job (crash recovery, issue #177). Long jobs keep their claim via a background heartbeat (`LeaseHeartbeat`, renewing at 1/3 of the window), so the lease does not need to cover a whole multi-chunk script run. All worker-originated lifecycle writes (`mark_running`, `mark_succeeded`, `mark_failed`, `record_worker_telemetry`) are **owner-fenced**: a worker whose lease lapsed gets `DomainError::Conflict` instead of overwriting the new owner's state.
- `AI_IMPORT_DEFAULT_PROMPTS_PATH` – optional deployment override documented for prompt packaging; the built-in fallback is `config/default_ai_prompts.toml`.
- `AI_IMPORT_USER_AGENT` – global override for the `User-Agent` sent by every AI provider HTTP client (default: `breakdown-rs-backend/<version> (ai-import)`).
- `AI_IMPORT_USER_AGENT_<PROVIDER>` – per-provider override, e.g. `AI_IMPORT_USER_AGENT_OPENCODE_GO` or `AI_IMPORT_USER_AGENT_OPENCODE` (takes precedence over the global variable). An empty or header-invalid value is ignored and the next source applies.

> **Descriptive `User-Agent` (issue #521).** The curated opencode / OpenCode-Go
> gateways triage requests on `User-Agent`; a blank, generic or reqwest-default
> agent (`reqwest/<version>`) is answered with `403`. Every provider client
> (catalog, Ollama, hosted chat) therefore sends the configured descriptive
> agent — additive transport metadata that leaves the issue #170 redirect /
> DNS-pin / no-proxy policy untouched. A `User-Agent` is not a credential.
>
> **Verify before attributing a `403`.** The same research note also links a
> `403` to model entitlement. When a real opencode-* call fails, capture the
> response body `code` and distinguish UA-triage from entitlement before
> changing the agent; do not commit to a one-cause fix without evidence.

> **Concurrency permits are cancellation-safe (issue #178).** The two
> `AI_IMPORT_MAX_CONCURRENT_JOBS_*` ceilings above are enforced by one owned
> row per permit in `ai_import.concurrency_permit`, not by an anonymous
> counter. `Drop` cannot `.await`, so a worker cancelled during shutdown could
> never run `release()`; recovery therefore lives in the permit itself. A
> permit's `Drop` hands its id to the in-process reclaimer task
> (`PgAiConcurrencyLimiter::spawn_reclaimer` — the fast path), and every row
> carries an `expires_at` lease that the next acquisition sweeps, so even a
> process kill self-heals within one lease window. Long holders renew via
> `PgAiConcurrencyPermit::renew` at `permit_renewal_interval` (1/3 of the
> window). All release paths are `DELETE ... WHERE id = $1`, so double-release
> is impossible.
>
> **The reclaim is bounded per permit (issue #528 follow-up).** A permit whose
> acquisition was cancelled mid-`commit` can still have its row locked by that
> transaction, so the reclaimer's delete is executed in a short transaction with
> `set_config('lock_timeout', …, true)` (`RECLAIM_LOCK_TIMEOUT`, 200 ms) and
> retried up to `RECLAIM_ATTEMPTS` (4) times with a linear backoff
> (`RECLAIM_BACKOFF_BASE`, 100 ms × attempt). Without the bound, one stuck row
> blocked the single reclaim loop head-of-line and delayed every later permit;
> without the retry, a single transient failure demoted the fast path to the
> lease floor (30 s). `reclaim_retry_budget()` is the analytic worst case per
> permit and is what integration tests budget against — never a guessed sleep.
> Only after the budget is exhausted is the row left to the lease.
>
> `AiWorkerRuntime::run_job` renews the permit while the operation runs, so a
> multi-hour script job cannot have its capacity swept out from under it (that
> would over-admit past the ceiling); a `Conflict` aborts the job rather than
> letting it run on capacity someone else now owns.
>
> **Composition-root wiring:** call `spawn_reclaimer()` and keep the returned
> `PermitReclaimer` alive for the process lifetime. Graceful shutdown has a
> required order, because every sender clone must be gone before the channel
> closes and permits hold one too: (1) cancel **and join** every task that may
> hold a permit, (2) drop every clone of the limiter, (3) await
> `PermitReclaimer::shutdown()`. Skipping a step leaves a live sender and the
> await hangs; dropping the handle instead aborts the task and silently
> downgrades those reclaims to lease-only — exactly the 900s capacity outage
> this design removes. Use `abort()` when the ordering cannot be guaranteed.

#### AI payload storage (durable source/preview blobs)

All three variables (`AI_PAYLOAD_S3_ENDPOINT`, `AI_PAYLOAD_S3_ACCESS_KEY`, `AI_PAYLOAD_S3_SECRET_KEY`) must be set to enable durable S3 storage for AI import payloads.

- `AI_PAYLOAD_S3_ENDPOINT` – S3 API endpoint for AI import payloads (e.g. `http://garage:3900`).
- `AI_PAYLOAD_S3_ACCESS_KEY` – S3 access key for AI payload storage.
- `AI_PAYLOAD_S3_SECRET_KEY` – S3 secret key for AI payload storage.
- `AI_PAYLOAD_S3_BUCKET` – S3 bucket name for AI payloads (default: `ai-import-payloads`).
- `AI_PAYLOAD_S3_TLS_ROOT_CERT` – optional PEM path of the pinned root CA for `https://` S3 endpoints.

> **Durable storage**: When all three required variables are set, AI import payloads survive API
> restarts. Pending jobs can resume, retries can reload source documents, and succeeded jobs
> continue serving previews.
>
> When `AI_IMPORT_ENABLED` is false, missing S3 variables are acceptable — the API wires
> `infra::ai::UnconfiguredAiPayloadStore`, which refuses every payload operation with
> `503` (never in-memory storage, which would accept payloads and drop them on restart;
> issue #181). When `AI_IMPORT_ENABLED` is true, all three S3 variables must be set or the
> API **fails to start** to prevent silent data loss.

> **Boot sequence**: Garage must be up and provisioned (bucket + access key) before the API
> starts. In dev, `./scripts/enable-dev-ai-import.sh` (issue #428) boots the AI overlay
> (`docker-compose.dev.ai.yml`), provisions the buckets/key and writes `.env.dev-ai.local` for the
> host-run API; the base dev Garage stays internal-only without the overlay. During first
> rollout set `PHOTO_GC_DRY_RUN=true` to observe orphan detection logs before enabling deletion.

#### AI payload GC (periodic cleanup)

- `AI_PAYLOAD_GC_ENABLED` – enable periodic cleanup (default: `true`).
- `AI_PAYLOAD_GC_INTERVAL_SECS` – sweep interval in seconds (default: `3600`).
- `AI_PAYLOAD_GC_MAX_AGE_SECS` – only cleanup payloads for jobs older than this (default: `604800` = 7 days).
- `AI_PAYLOAD_GC_BATCH_SIZE` – max terminal-state jobs per run (default: `1000`).
- `AI_PAYLOAD_GC_DRY_RUN` – log-only mode (default: `false`; set `true` for first rollout).

> **AI payload GC**: A periodic worker cleans up Garage payloads for terminal-state jobs
> after the configurable grace period. The worker uses a Postgres advisory lock to prevent
> concurrent sweeps. Set `AI_PAYLOAD_GC_DRY_RUN=true` for the first rollout to observe
> deletion logs before enabling actual cleanup.
>
> **Terminal means unclaimable (issue #181).** The sweep covers exactly
> `succeeded`, `dead_letter` and `payload_unavailable`. `failed` is **never**
> swept — it is the *retryable* backoff state, and sweeping it deleted the source
> document of jobs that were still scheduled to run.
>
> Do not "refine" this to sweep `failed` once `retries >= max_retries`. The claim
> predicates match `status = 'failed' AND (next_attempt_at IS NULL OR
> next_attempt_at <= now())` and **never consult `retries`**, so an exhausted
> `failed` row is still handed to the next worker. Nothing leaks as a result:
> `mark_failed` dead-letters a job in the same statement that exhausts its budget,
> so a `failed` row is by construction one that still has a future.
>
> **The sweep is stateful (issue #206).** Each deleted payload is recorded in
> `ai_import.ai_payload_cleanup`, keyed `(job_id, payload_kind)`, and the sweep
> anti-joins those marks so a job is selected only while it still owes a
> payload. Without the marks the oldest `batch_size` jobs were re-selected on
> every run forever: deletions are idempotent so nothing broke, but the S3
> round-trips were re-paid, the run-history counters re-counted the same
> deletions, and any job behind the `LIMIT` never got swept at all — retention
> silently stopped being enforced. The `LIMIT` is a rate limit, not a horizon.
>
> **Only real deletions may be marked.** A mark hides the payload from every
> future sweep, so it must never outrun the deletion:
> - deleted → marked;
> - **not found → marked** (the goal state holds, and a terminal job can never
>   be re-claimed to recreate the payload, so re-probing it is pure waste);
> - failed → **not** marked, so the next sweep retries it;
> - dry run → **not** marked, or observation mode would permanently hide the
>   very objects it was meant to report.
>
> Marks are flushed *before* the run-history row and *before* the early return
> on the first deletion error, so one failure cannot discard the marks its
> siblings in the batch earned. A sweep must never touch `updated_at` on the
> job row — that column is both the retention clock and the sweep's `ORDER BY`
> key, so writing it there would reset the window it measures.

#### AI import restart recovery (issue #181)

AI import payloads live in Garage (`AI_PAYLOAD_S3_*`), so a process restart does not
lose them. Behaviour per job status after a restart:

| Status | Behaviour |
|---|---|
| `pending` | Runnable; the next worker claims it and loads the source from durable storage. |
| `running` | Its worker is gone; the claim lease expires and another worker reclaims it, releasing the orphaned permit. |
| `failed` | Runnable once `next_attempt_at` is due — the claim predicate ignores `retries`. Payloads are **never** GC'd. |
| `dead_letter` | Terminal; payloads GC-eligible after retention. `mark_failed` lands a budget-exhausted job here directly. |
| `succeeded` | Preview served from durable storage; apply reloads it. GC-eligible after retention. |
| `payload_unavailable` | Terminal and **non-resumable**: never claimed, never retried. |

A worker that cannot load a payload because it is **absent** (`DomainError::NotFound`)
calls `AiImportQueue::mark_payload_unavailable`, which moves the job to
`payload_unavailable` immediately, bypassing the remaining retry budget — every retry
could only re-discover the same absence while consuming a claim and a concurrency
permit. A worker that cannot load it because storage is **unreachable**
(`ServiceUnavailable`) still fails retryably: that is transient, and the bytes may well
still be there. Never collapse these two cases.

The composition root must never hold an in-memory payload store: with AI import
disabled, `main.rs` wires `infra::ai::UnconfiguredAiPayloadStore`, which refuses every
operation with `ServiceUnavailable` (deliberately not `NotFound`, which would
dead-letter jobs). `MemoryAiPreviewStore` is test-only.

#### AI provider circuit breaker (issue #871)

Two nested retry layers exist and must not be confused:
**in-attempt** (`AI_IMPORT_MAX_ATTEMPT_RETRIES`, per chunk) and **job-level**
(`AI_IMPORT_MAX_RETRIES`, per job). They used to be one knob, which is how one
chunk could cost 25 paid calls.

A **durable** breaker per `(provider, model)` pair sits in front of both:

- **Only `closed` admits a claim.** The filter is one `NOT EXISTS` predicate on
  all four claim paths (`claim_next`, `claim_next_kind` and their reconciling
  variants). `retry_at` is deliberately **not** part of it: it is the probe
  schedule, not a claim gate — filtering on it would lift the filter the instant
  a probe became due and drain the queue instead of running one probe.
- **Only retryable provider failures count.** A revoked key, a bad model or an
  entitlement 4xx is `dependency.auth-failed`-class permanent (#637) and must
  never open a breaker: that would convert one user's misconfiguration into an
  outage for everyone on the endpoint.
- **A held job is `failed` with `retries` unchanged and one attempt row per hold
  *series* (issue #942 W2).** The wire carries an additive `provider_hold`
  (`provider`, `model`, `reason_code`, `state`, `until`, `hold_deadline`,
  `chunks_done`); `last_error` keeps #822's narrative so an older client still
  renders. `provider_hold` is cleared by every other lifecycle write, with
  exactly one exception: the hold-expiry write keeps it with `state = expired`,
  because that marker is the only durable signal separating an expiry from a
  spent retry budget.
  Do not "restore" the pre-#942 rule of appending **no** attempt row: it made the
  most common real provider state (repeated failures → hold) the one state with
  zero diagnosable evidence — `last_error` held a bare problem code and the
  attempt history stayed empty, so a client-timeout hold, an HTTP-status hold and
  a bounded-body hold were indistinguishable from Postgres alone. The row is
  written by the **first** hold of a series (`provider_hold_series_started_at`
  was NULL before it), carries the bounded failure narrative in `error_summary`
  and the fired registered code in `error_code`, and is `retryable = TRUE`
  (a hold resumes; a dead letter does not). A re-hold inside the same series
  appends nothing, and `retries` stays untouched on every path. The sweeper's
  `hold_runnable_jobs` path (a job enqueued while the breaker was already open)
  writes no row — it has no first-hand failure — so a held job may legitimately
  have none.
- **Recovery is a probe, never elapsed time.** "Elapsed ⇒ closed" would resume
  paying into a still-broken endpoint. The probe is the model-catalog read the
  AI-config screen already uses (no tokens), authenticated with **one actively
  held job's own vaulted key** — never a synthetic credential — and Ollama is
  probed **unauthenticated** (`GET {base}/api/tags`), because the hosted catalog
  client requires a non-empty key and always sends a bearer token, which would
  leak one to a plain-HTTP curated origin (CWE-319). The probe judges
  reachability only: it never retires or terminalizes a job.
- **The probe is a task, not a claimed job.** Only `closed` admits a claim, so no
  worker runs for the pair when the probe is due. It runs as lease CAS → request
  **outside any transaction** → fenced result, so a hung probe cannot hold the
  row lock and lock out the takeover its own lease exists to allow.
- **Mid-run abort happens at the chunk boundary.** The in-flight request is not
  aborted (an aborted HTTP request is not refunded), so the overspend bound is
  exactly one chunk per worker.
- **Quota exhaustion has its own code (issue #942 W3).** An upstream
  `402 Payment Required` (EURouter's budget/spend cap) and a `429` whose body
  matches the provider's quota markers both produce
  `DomainError::LlmProviderQuotaExhausted` → `ai-import.provider-quota-exhausted`
  (402), superseding #822 D-X1 / #927's reuse of
  `ai-import.llm-provider-unavailable`. The split is presentation-only: the
  variant stays `is_retryable() == false`, so it dead-letters immediately, and
  `retry_bounded` still refuses to count it toward the breaker — an empty account
  must never open the deployment-wide `(provider, model)` breaker for other
  users (#927's invariant, pinned by
  `provider_gate_tests::a_quota_exhausted_provider_failure_is_terminal_*`).
- **Operability:** the durable row plus the `#871 provider breaker` log marker;
  see `docs/operations/runbooks.md` §16. `GET /v1/health` gains **no** provider
  check (unauthenticated, 2 s timeout, no credential).

#### Chunk-level resume (issue #871, workstream B)

A retried attempt continues at the first chunk that never completed instead of
re-extracting from chunk 0. The issue's evidence is a 42-chunk document that died
at chunk 25 **three times**: the same ~25 chunks paid for three times.

- **The store.** `ai_import.ai_import_job_chunk` holds one row per completed chunk
  — the parsed `ScriptContext`-shaped result plus that call's usage. The stored
  unit is the **paid call**, which is the only unit that matters for cost. A
  table rather than a JSONB column because one bounded insert per chunk beats
  O(n²) bytes, and because `ai_import_job.updated_at` is load-bearing (retention
  clock, GC `ORDER BY`, ETA anchor) and must not be written once per chunk.
- **The cursor is derived, never stored**: the length of the contiguous stored
  prefix. `MAX(chunk_index) + 1` over `0, 1, 3` would answer 4 and quietly omit
  chunk 2 from the preview; a stored cursor can disagree with the rows after a
  lost write. A row beyond a hole is unreachable (the merge is a prefix walk), so
  it is deleted with `#871 chunk resume hole at <index>`.
- **Every chunk write is fenced by a row LOCK, not a predicate.** Under READ
  COMMITTED a bare `INSERT … SELECT … WHERE status = 'running' AND worker_id = $2`
  reads the job row without a lock, so another session can reclaim the job and
  rewrite `extraction_key` between the read and the commit — and the stale write
  lands anyway. `SELECT … FOR UPDATE` on the job row, and the invalidation path
  takes the same lock in the same order, so the two serialize.
- **The fingerprint is what makes resume safe.** `sha256(document_digest |
  provider | model | sha256(effective prompt) | chunker_version)`; a mismatch
  deletes the whole set and restarts at 0 (`#871 chunk resume invalidated:
  <components>`), because a preview must never mix two chunkings, two models or
  two prompts. The components are stored next to the hash so the log can *name*
  what changed. Bump `core::ai::preview::CHUNKER_VERSION` whenever
  `extract_scenes` changes what a chunk is.
- **Progress and ETA measure from the resume point.** `progress.resumed_from`
  carries "n chunks already stored"; `progress.chunk` keeps its documented
  meaning (1-based index of the last completed chunk **of this attempt**). A
  client derives the rate from `chunk - resumed_from` and the remaining count
  from `chunks_total - chunk` — using the absolute counter would read "25 chunks
  in one second" and then declare a healthy successor chunk stalled.
- **Cost: every paid call is counted once.** The chunk row carries its usage, and
  `ON CONFLICT … DO UPDATE` *replaces* a re-run chunk's usage instead of adding
  it, so the completion snapshot sums all chunks regardless of which attempt paid
  for them. **One case is deliberately uncounted:** a call whose response arrived
  but whose row never persisted (a kill between response and insert). Its spend is
  bounded by one chunk per crash, it appears in no other surface, and it is not
  guessed at.
- **Cleanup.** Terminal transitions (`mark_succeeded`, `mark_payload_unavailable`,
  the dead-letter branch of `mark_failed`) delete the job's chunk rows in the same
  statement; a job that merely backs off keeps them — that is the resume. The
  payload-GC sweep deletes them with the blobs (skipped in dry-run), and
  `dev_reset` registers the table before the job delete.
- A schedule import is ONE extraction unit, so it has no chunk resume; the port is
  only consulted by the script worker.

#### Retry precedence (issue #871, workstream C)

Two nested layers, and **which one wins is a rule, not an accident**:

| Situation | What happens | Why |
|---|---|---|
| A retryable provider failure, breaker still **closed** | `retry_bounded` retries in-attempt, `AI_IMPORT_MAX_ATTEMPT_RETRIES` times (default 2) | a blip is cheap to absorb; the permit stays held (releasing and re-acquiring per retry would let another job interleave between two calls of the same chunk) |
| The breaker **opens** (threshold consecutive failures for the pair) | every held/runnable job of that pair takes the **hold** path; `next_attempt_at` = the breaker's `retry_at` | the whole fleet re-probes at ONE instant instead of a per-job stagger, which is what makes the single CAS prober cheap and recovery fast |
| A **non-provider** retryable failure (mapping DB, payload storage, pricing read model) | the ordinary per-job curve `1 min · 2^retries`, capped at 6 h | that curve was designed for exactly these, and the breaker must not swallow them — they say nothing about the endpoint |
| The **hold expires** (`AI_IMPORT_MAX_PROVIDER_HOLD_SECS`) | `dead_letter` with the provider narrative, `retries` **unchanged**, exactly one attempt row | the document did not fail, the provider did; the operator's "documents that failed" count must not be inflated by infrastructure |

**The permit is held across in-attempt retries and released with the attempt.** A
hold *ends* the attempt, so a waiting job occupies no capacity. The window one
attempt can occupy a permit is therefore a computed number, not a guess:

```
(1 + AI_IMPORT_MAX_ATTEMPT_RETRIES) × (1 + inner_retries) × AI_IMPORT_REQUEST_TIMEOUT_SECS
  + AI_IMPORT_MAX_ATTEMPT_RETRIES × max(30 s, MAX_IN_ATTEMPT_HINT_SECS)
```

with `inner_retries = 2` for hosted providers (`HOSTED_INNER_RETRIES`) and `3` for
Ollama (`OLLAMA_INNER_RETRIES`) — the clients re-request a truncated/malformed
answer *inside* one attempt, so the two layers **multiply**. The backoff term is a
**ceiling over both** the computed cap (`MAX_ATTEMPT_BACKOFF_SECS`, 30 s) and the
server-hint clamp (`MAX_IN_ATTEMPT_HINT_SECS`, 120 s) introduced by issue #926,
because `retry_bounded` sleeps `max(computed, hint)`. With the defaults:
**22 min** hosted, **28 min** Ollama (pre-#926 these were 19/25 min, and a
`const` assertion in `bounds.rs` keeps the ceiling ≥ both clamps).
`AiImportBounds::attempt_worst_case_secs`
is the authoritative rendering and is asserted in `bounds_tests.rs`; the inner
counts are declared in `core` and read by the clients, so the arithmetic cannot
drift from the code it describes.

> **Intentional cost change (D-C1).** The in-attempt retry count dropped from
> **5 to 2** in issue #871. Before the split, one knob governed both layers, so a
> single chunk could cost `5 × 5 = 25` paid calls before anything surfaced, each
> holding a permit for up to `AI_IMPORT_REQUEST_TIMEOUT_SECS`. Three attempts per
> chunk is enough to tell a blip from an outage, and the breaker — not a long
> retry ladder — is what handles the outage. This is a deliberate behaviour and
> cost change, not a regression: an operator who wants the old ladder can set
> `AI_IMPORT_MAX_ATTEMPT_RETRIES`, and `AI_IMPORT_MAX_RETRIES` keeps its job-level
> meaning untouched.

#### Provider retry hints (issue #926)

Every hosted provider we integrate signals a rate limit with `429` plus
`Retry-After` / `X-RateLimit-*`. Since issue #926 that header is **acted on**:
the transport parses it into a `RetryHint`, the classification attaches `wait` to
the failing `DomainError::ServiceUnavailable` as `retry_after`, and the four
schedulers that already exist use it as a **minimum** delay.

**The one rule that must not be broken:** the hint is never slept through inside
the provider call. That call holds an `ai_import.concurrency_permit`, so an
in-request sleep would hold capacity for the hint's whole duration — the
nested-hold anti-pattern #871 removed (25 paid calls / 19–25 min permit-hold per
chunk). The hint propagates **up** as data instead.

| Scheduler | How the hint is used | Clamp |
|---|---|---|
| `workers::retry_bounded` (in-attempt chunk retry) | the wait becomes `max(computed backoff, hint)`; jitter stays on the computed backoff | `MAX_IN_ATTEMPT_HINT_SECS` = **120 s**, because the pause holds a permit |
| `queue::mark_failed` (job-level retry) | `next_attempt_at = now + max(1 min·2^retries, hint)` | **6 h**, the ladder's own literal cap; a larger hint is clamped and logged at `warn` |
| `core::ai::provider_health` (breaker probe schedule) | `retry_at = now + max(open window, hint)` — the probe selector already reads `retry_at <= now()`, so a hint-unexpired pair is not probed | `MAX_PROBE_DEFER_SECS` = `MAX_OPEN_SECS` (30 min): a probe is never deferred beyond the breaker's own maximum window |
| `ProviderHold.until` (hold series) | inherits `retry_at`, so a held job's `next_attempt_at` honours the hint too | bounded by `AI_IMPORT_MAX_PROVIDER_HOLD_SECS` for the whole series |

Notes that keep this honest:

- **No new environment knob.** Both clamps are constants named above; only a
  future *policy* change (not a deployment tweak) would justify a knob, and it
  would need bounds plus startup logging like the existing ones.
- **A hint never changes the classification.** It does not touch the variant,
  the registered code (`ai-import.llm-provider-unavailable`), the HTTP status or
  `is_retryable()`. The *body*, not the header, is what separates an exhausted
  quota from a burst — see "Quota exhaustion vs rate limit (issue #927)".
- **The narrative names the rate limit.** The attempt row's `error_summary`
  says "… asked to wait Ns", and both the text and the typed field come from the
  one `retry_after` input at the classification boundary — `core` builds no
  presentation string (ADR-031).
- **A bad hint is never an error.** An absent, unparsable or absurd header
  degrades to "no hint" (or the one-day `MAX_SERVER_HINT` cap in the parser), and
  the request keeps its ordinary outcome.
- **A hint-less failure never shortens a deferral an earlier hint earned.** The
  `retry_at` write is unconditional, so the deadline is data on the row and
  `BreakerCounters` carries it into the state machine: while it is unexpired the
  probe keeps the later of it and the newly computed time. Without that, the
  60 s open window of the next ordinary `503` would pull a 10-minute rate-limit
  deferral forward and the probe would fire into a provider that is still
  rate-limiting us. An **expired** stored deadline is discarded — nothing is left
  to protect.
- **Not honoured, deliberately:** the decision-scoring pass
  (`decision_scoring::decide_with_quick_retry`) and the pricing-catalog ticker.
  The first carries the hint into the job-level retry but keeps its own single
  fixed pause (its policy is a bounded two-call pass, not a scheduling loop); the
  second has no retry loop at all.

#### Quota exhaustion vs rate limit (issue #927)

A provider `429` is **two conditions**, and only the response body tells them
apart. A rate limit (RPM/TPM) is fixed by waiting; a quota exhaustion is not —
retrying burns paid calls that are answered `429` again, each holding a
concurrency permit for up to `AI_IMPORT_REQUEST_TIMEOUT_SECS`, and then spends
the whole job retry budget to learn what the first response already said.

`client::classify_provider_body(provider, body) -> RateLimitVerdict` decides on
**evidence from the provider's own error text** (the #521 rule: verify before
attributing), and `classify_http_status_rich(…, verdict)` maps the terminal
verdict to `DomainError::LlmProviderQuotaExhausted`. That variant keeps the
**existing** registered code (#822 D-X1: no new code for provider narratives) but
is non-retryable, so the job dead-letters on the first attempt with the provider
code in its narrative.

| Provider | Terminal markers | Everything else on `429` |
|---|---|---|
| `openai`, `neuralwatt`, `opencode`, `opencode-go` | `insufficient_quota`, `credit_balance_exhausted`, `billing_hard_limit_reached` | retryable |
| `gemini` | `perdayperproject`, `per_day_per_project` (the RPD quota id in `error.details[].metadata.quota_limit`) | retryable |
| `openrouter` | `free-models-per-day`, `free_models_per_day` | retryable |
| `eurouter` | *(none — budget caps are `402`, its `429` is plan RPM)* | retryable |
| `ollama` | *(none — self-hosted)* | retryable |

Rules that must not drift:

- **The table is curated `const` data in the transport layer**, next to
  `CuratedProviderUrls`, and is **not** user-configurable — the same trust rule
  as the curated URLs. A new provider ships retryable until its evidence has been
  verified against a live response.
- **The conservative default is retryable.** An empty body, an unparsable one (an
  HTML gateway page), a read that failed, or an unknown code stays
  `RateLimited` + `debug`. A wrong "non-retryable" verdict dead-letters a job a
  retry would have saved; a wrong "retryable" one costs one attempt.
- **The verdict only narrows a `429`.** A `5xx` carrying a quota-looking body is a
  gateway fault and must never dead-letter a job. `402`/`403` keep their existing
  non-retryable rejection (EURouter budget caps, opencode entitlement).
- **`X-RateLimit-Remaining: 0` is not evidence**: an RPM window reaches zero the
  same way. Header-only turnstiles stay retryable; the #926 hint still schedules
  the retry.
- **The body read is bounded in bytes AND in time**
  (`client::MAX_ERROR_BODY_BYTES` = 1 KiB, and a deadline of
  `client::error_body_budget(request_timeout)` = `min(ERROR_BODY_DEADLINE = 5 s,
  AI_IMPORT_REQUEST_TIMEOUT_SECS)` — the knob is configurable down to 1 s, so the
  read can never outlive the request it belongs to; streamed chunk by chunk,
  never `text()`/`bytes()`): a chatty or hostile error page must not stream while
  a permit is held, and a marker behind the bound is deliberately not seen
  (conservative default). Say it as **limiting** the permit hold, not as always
  ending it before the timeout — at the knob's 1–5 s floor the budget equals the
  timeout, so the read may last as long as the request itself.
- **An incomplete read is not evidence.** The reader returns
  `ErrorBody { text, complete }`; an IO error or the deadline leaves
  `complete = false`, which keeps the `429` retryable even when the bytes that
  arrived look like a quota code (a proxy-cut stream may have lost the part that
  changes the meaning). A stream that ends on its own end — or on the deliberate
  byte bound — classifies normally.
- **The narrative names the matched code.** The verdict carries the curated
  marker that fired (`QuotaExhausted { marker }`), so the attempt row says
  `… no quota left (insufficient_quota)` even when a long `error.message` pushes
  the raw code past the 400-character detail truncation.
- **A terminal verdict never moves the breaker counter.**
  `retry_bounded` records a provider failure only for a *retryable* one; counting
  a quota exhaustion would let three of them open the breaker, and the hold that
  follows would park a job that has nothing left to wait for.

#### Durable apply run (issue #899)

The **apply** used to be request-scoped: `apply_ai_import` awaited
`ApplyWorker::apply_script` in the handler future, so a client that vanished
(Android Doze, Wi-Fi→cellular handover, a closed socket) dropped the future and
the run stopped mid-row. It is now a work item on the job row, exactly like the
preview job.

| Transition | Port method | Writes |
|---|---|---|
| dispatch | `request_apply_run(id, run_id, &ApplyRunRequest)` | `apply_state = requested`, `apply_request` (JSONB), `apply_result = NULL`, the claim (`apply_run_id`, `apply_claim_at`, `apply_run_seq + 1`) |
| worker claim | `begin_apply_run(id, takeover_run_id)` | `requested` → `running` **adopting** the dispatching run id, or a stale `running` → `running` under `takeover_run_id` (the dead owner's writes then fail the fence) |
| success / failure | `complete_apply_run(id, run_id, &summary)` / `fail_apply_run(id, run_id, code)` | `done`/`failed` + `apply_result` (`ApplyRunOutcome`), `apply_progress = NULL`, `apply_run_id = NULL` — owner-fenced, `Conflict` for a displaced run |
| poll | `requested_apply_runs(limit)` | the rows a worker may claim: `requested`, or `running` silent for `ApplyProgress::STALE_AFTER` (the same window the single-flight steal uses) |

Rules that must not drift:

- **The handler never executes a run.** `POST /apply` validates, persists and
  answers `202 ApplyRunAccepted`. Row work happens in
  `api::apply_runner::spawn_apply_run_worker` → `ApplyRunner::run_claimed`.
- **`apply_request` is the reviewer's decision set**, resolved at the API edge
  (target episode/season/block, mapping decisions, group targets, day decisions,
  acknowledgements, continuity selections, the season's category vocabulary, the
  episode labels). The worker must never re-derive it from a projection (CQRS
  boundary) and never read it back out to a client — it is not in the job DTO.
- **The outcome is persisted, not returned.** The terminal frame of
  `GET /jobs/{id}/apply-events` and `GET /jobs/{id}` serve it (`apply_state` +
  `apply_result`); a failed run carries the registered problem **code**.
- **`ApplyProgress` is cleared only by the terminal transitions.** A run killed
  mid-flight leaves `running` + a stale stamp, which the takeover path reclaims —
  do not re-introduce a drop guard on the dispatched path.
- **A live run renews its own claim** (`renew_apply_run`, issue #911). Every
  single-flight predicate above is silence-based, which a *script* apply satisfies
  with its progress frames and a *schedule* apply cannot: it is one merge loop
  over the project's existing scenes and days and publishes nothing, so before
  #911 a schedule run that outlived `ApplyProgress::STALE_AFTER` was taken over
  **while it was still executing**. `ApplyRunner::run_claimed` therefore runs the
  execute future under `infra::ai::with_apply_run_lease` (interval = a third of
  that window). The renewal rides the run's own future instead of a spawned task,
  so it dies with the task and a crashed replica still becomes stealable after one
  window. It writes `apply_claim_at` **only** — never the payload (that would
  invent progress), never `apply_run_seq`, never a `pg_notify` — and `false`
  (displaced, or the run already finished and freed the slot) stops the loop.
  All four silence predicates (both steals, the takeover and the poll) compare the
  **newer** of the payload's `updated_at` and that lease stamp
  (`COALESCE(GREATEST(…, apply_claim_at), updated_at)`), so the renewal also covers
  a script run that is between frames — a schedule run has none at all.
  `ApplyRunState::owner_silence_at` mirrors that `GREATEST`, because the age a
  client reads in the `409` must describe the same decision the server makes.
- **Shutdown joins**: the loop aborts-and-joins its in-flight runs before the
  pool teardown; an interrupted run is recovered by the staleness window, never
  rolled back (the protocol stays idempotent-and-converging).
