<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: gpt-5.6-luna (pi) -->

# Proposal: Wire AI concurrency limiter into main.rs (issue #214)

## Summary

Wire `PgAiConcurrencyLimiter` / `AiWorkerRuntime` into the composition root
(`backend/crates/api/src/main.rs`) and implement the graceful-shutdown sequence
that the cancellation-safe permit design (#178, PR #213) requires.

Today the limiter is public API that nothing constructs: `grep` finds no
`PgAiConcurrencyLimiter`, `AiWorkerRuntime`, `ScriptImportWorker` or
`ScheduleImportWorker` in `crates/api/src`. The shutdown contract is therefore
**documentation only** and nothing enforces it.

## Problem

`PermitReclaimer::shutdown()` waits for the reclaim channel to close. The channel
has **two** kinds of sender clone: one per `PgAiConcurrencyLimiter` clone, and one
per **live `PgAiConcurrencyPermit`**. So the composition root must follow a
specific order:

1. cancel **and join** every task that may hold a permit;
2. drop every clone of the limiter;
3. `PermitReclaimer::shutdown().await`.

Getting this wrong hangs shutdown (skip 1/2) or silently reintroduces the
capacity outage #178 removed (abort instead of join).

## Design

### 1. Construct the limiter + reclaimer in main.rs

When `AI_IMPORT_ENABLED` is true:

- Build `AiImportBounds::from_env()` (already exists).
- Construct `PgAiConcurrencyLimiter::new(pool, bounds.max_concurrent_jobs_global, bounds.max_concurrent_jobs_per_user)`.
- Call `.spawn_reclaimer()` → keep the `PermitReclaimer` for the process lifetime.
- Build `AiWorkerRuntime::new(Arc::new(limiter))`.

### 2. Spawn AI import worker loops

Add a `worker_loop` module to `crates/infra/src/ai/` that exposes:

- `spawn_script_import_worker(...)` → `JoinHandle<()>`
- `spawn_schedule_import_worker(...)` → `JoinHandle<()>`

Each worker loop:
- Polls `queue.claim_next_kind_reconciling(worker_id, kind)`.
- On `Some(job)`, routes the job through
  `runtime.run_job_as(job.user_id, worker_id, || worker.run_once_with_permit(...))`
  so the permit lifecycle (acquire → renew → release) and the `AiJobGuard`
  (in-flight tracking for `drain()`) are managed by the runtime.
- On `None`, sleeps briefly (with `CancellationToken` awareness) and retries.
- On `Ok(None)` from `run_job` (capacity saturated), releases the claim via
  `queue.release_claim(...)` so the job is immediately runnable by another worker.

The workers are constructed with the same dependencies the handlers already use:
`PgAiImportQueue`, `OpenAiCompatibleChatClient` (or configured provider),
`Arc<dyn AiPreviewStore>`, `Arc<dyn AiDocumentSource>`, `PdfTextExtractor`,
provider/model/prompt from `AiConfig`, and `AiImportBounds`.

### 3. Graceful shutdown

- Add a `CancellationToken` (tokio-util) for the worker tasks.
- Replace `axum::serve(listener, app).await?` with
  `axum::serve(listener, app).with_graceful_shutdown(shutdown_signal(...))`.
- `shutdown_signal` waits for SIGTERM/SIGINT and cancels the token.
- After the server future resolves, run the 3-step sequence:
  1. `runtime.drain().await` — bounded by `DRAIN_TIMEOUT` (15s). This is the
     "cancel and join" for permit-holding work: the `AiJobGuard` count must reach
     zero. If it times out, log `warn!` and proceed (an orchestrator SIGKILL would
     be strictly worse — it would skip the reclaims entirely).
  2. Drop all `PgAiConcurrencyLimiter` clones (the runtime handle + the limiter
     handle held by main).
  3. `reclaimer.shutdown().await`.

### 4. Guard behind AI_IMPORT_ENABLED

The entire limiter + worker + shutdown path is gated behind
`AI_IMPORT_ENABLED`. When disabled, main.rs is unchanged.

## Required changes

### `crates/infra/src/ai/worker_loop.rs` (new)

- `spawn_script_import_worker` / `spawn_schedule_import_worker` functions.
- Each returns a `JoinHandle<()>`.
- Routes jobs through `AiWorkerRuntime::run_job_as`.
- Respects a `CancellationToken` for shutdown.

### `crates/infra/src/ai/mod.rs`

- `pub mod worker_loop;`
- Re-export the spawn functions.

### `crates/api/src/main.rs`

- Import the new spawn functions, `PgAiConcurrencyLimiter`, `AiWorkerRuntime`,
  `PermitReclaimer`, `CancellationToken`.
- When `AI_IMPORT_ENABLED`: construct limiter + reclaimer + runtime, spawn
  workers, store handles.
- Add `shutdown_signal` (SIGTERM/SIGINT).
- `axum::serve(...).with_graceful_shutdown(...)`.
- After server resolves: drain → drop limiter clones → `reclaimer.shutdown().await`.

### `crates/api/Cargo.toml`

- Add `tokio-util` with `rt` and `features = ["rt"]` (for `CancellationToken`).
  (Check if already present.)

### Tests

- **Integration test** (`crates/integration-tests/tests/ai_concurrency_shutdown.rs`):
  - Assert that after a simulated shutdown no permit rows remain (reclaims were
    drained, not aborted).
  - Assert the shutdown sequence terminates within budget even when a task holds
    a permit longer than the drain timeout.

## Acceptance criteria

- [ ] `main.rs` constructs the limiter with `spawn_reclaimer()` and holds the
  `PermitReclaimer` for the process lifetime.
- [ ] AI import jobs acquire capacity through `AiWorkerRuntime`, so the
  `AI_IMPORT_MAX_CONCURRENT_JOBS_*` ceilings are actually enforced at runtime.
- [ ] On SIGTERM the process cancels **and joins** permit-holding tasks, drops all
  limiter clones, then awaits `PermitReclaimer::shutdown()`.
- [ ] Shutdown **cannot hang**: the drain/shutdown sequence is bounded, and
  exceeding the budget falls back to `abort()` with a `warn!` rather than blocking
  exit.
- [ ] A test asserts that after a simulated shutdown no permit rows remain.
- [ ] A test asserts the shutdown sequence terminates within its budget even when
  a task holds a permit longer than the drain timeout.

## Version bumps

| Crate | Previous | New | Bump type | Reason |
|---|---|---|---|---|
| `api` | 0.6.1 | 0.6.2 | PATCH | Wires existing infra AI concurrency API into composition root; no new public API |
| `core` | 0.7.0 | 0.7.0 | none | No domain change |
| `infra` | 0.12.0 | 0.12.0 | none | No infra API change; worker_loop is additive but internal to existing AI feature |
