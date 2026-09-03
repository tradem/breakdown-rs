---
description: AI import - configuration, concurrency permits, payload storage, GC and restart recovery.
applyTo:
  - "crates/*/src/ai/**"
  - "crates/integration-tests/tests/ai*"
  - "config/default_ai_prompts.toml"
---

# AI import (`add-ai-script-and-schedule-import`)

#### AI import (`add-ai-script-and-schedule-import`)

- `AI_IMPORT_ENABLED` – enable AI import routes/workers (default: `false`; accepted values: `true`, `1`, `yes`).
- `AI_IMPORT_MAX_CHUNKS_PER_SCRIPT` – maximum script scene chunks per job (default: `128`; bounded to `1..=10000`).
- `AI_IMPORT_MAX_TOKENS_PER_REQ` – maximum output tokens per LLM request (default: `8192`; bounded to `1..=1000000`).
- `AI_IMPORT_MAX_CONCURRENT_JOBS_GLOBAL` – global in-flight job ceiling (default: `16`).
- `AI_IMPORT_MAX_CONCURRENT_JOBS_PER_USER` – per-user in-flight job ceiling (default: `2`).
- `AI_IMPORT_MAX_DOCUMENT_BYTES` – maximum source document size (default: `20971520`).
- `AI_IMPORT_REQUEST_TIMEOUT_SECS` – provider request timeout (default: `120`).
- `AI_IMPORT_MAX_RETRIES` – maximum queue retries before dead-lettering (default: `5`).
- `AI_IMPORT_LEASE_SECS` – worker claim lease in seconds (default: `900`). An out-of-range number is clamped to `30..=86400`; only absent/unparsable values fall back to the default. A claim records `worker_id` + `lease_expires_at`; once the lease expires another worker may reclaim the `running` job (crash recovery, issue #177). Long jobs keep their claim via a background heartbeat (`LeaseHeartbeat`, renewing at 1/3 of the window), so the lease does not need to cover a whole multi-chunk script run. All worker-originated lifecycle writes (`mark_running`, `mark_succeeded`, `mark_failed`, `record_worker_telemetry`) are **owner-fenced**: a worker whose lease lapsed gets `DomainError::Conflict` instead of overwriting the new owner's state.
- `AI_IMPORT_DEFAULT_PROMPTS_PATH` – optional deployment override documented for prompt packaging; the built-in fallback is `config/default_ai_prompts.toml`.

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
> starts. See `docker-compose.dev.yml` for the internal-only Garage service. During first
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

