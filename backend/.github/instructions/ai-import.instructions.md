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
- `AI_IMPORT_MAX_ATTEMPT_RETRIES` – **in-attempt** retries of one chunk's provider call (default: `2`, bounded `0..=10`). Since issue #871 this is a *second* knob: one knob allowed `5 × 5 = 25` paid calls for a single chunk before anything surfaced, each holding a concurrency permit for up to `AI_IMPORT_REQUEST_TIMEOUT_SECS`. `1 + 2 = 3` attempts per chunk is enough to tell a blip from an outage. The analytic worst case of one attempt across **both** nested layers is `(1 + max_attempt_retries) × (1 + inner_retries) × request_timeout_secs + max_attempt_retries × 30 s` = **19 min** hosted (`inner = 2`) / **25 min** Ollama (`inner ≤ 3`), because the clients re-request a truncated/malformed answer inside one attempt.
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
- **A held job is `failed` with `retries` unchanged and no attempt row.** The
  wire carries an additive `provider_hold` (`provider`, `model`, `reason_code`,
  `state`, `until`, `hold_deadline`, `chunks_done`); `last_error` keeps #822's
  narrative so an older client still renders. `provider_hold` is cleared by every
  other lifecycle write, with exactly one exception: the hold-expiry write keeps
  it with `state = expired`, because that marker is the only durable signal
  separating an expiry from a spent retry budget.
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
