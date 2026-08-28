<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.2 (neuralwatt) -->

# Proposal: Terminalize permanent processing errors in the AI import worker loop (issue #222)

## Summary

When `ScheduleImportWorker::process` (or `ScriptImportWorker::process_text`)
returns a processing error, the worker loop returns it to `spawn_worker`,
which only logs and backs off. The queue claim stays active until lease
expiry, blocking the job from being reclaimed and retried by another worker.

Not all processing errors are transient. A bad base URL, a rejected API key,
or a permanently malformed prompt will fail every retry until the lease
expires. These should fail the job terminally (via `mark_failed` with
`retryable = false`) rather than consuming a claim for the whole lease window.

## Problem

The worker-loop edge is `handle_job_result` (issue #214), which today does:

- `Ok(Some(_))` → job already `mark_succeeded`, return `Ok(())`;
- `Ok(None)` → capacity saturated, release the claim;
- `Err(error)` → propagate to `spawn_worker`, which logs and backs off.

On the `Err` path the job remains `running` with the worker's lease until
`lease_expires_at` — a *permanent* failure (e.g. `ValidationError` from a
401-rejected API key, a base-URL redirect policy rejection, a malformed
prompt/response, an unparseable CSV) therefore consumes the whole
`AI_IMPORT_LEASE_SECS` window before another worker can reclaim it.

The script worker already marks some of its own failures via its internal
`fail` helper, but the schedule worker deliberately has none
("`process` surfaces its own errors to the caller"), and neither worker marks
failures from the extract/preview-store/telemetry/succeeded steps. The
classification belongs at the loop edge so every processing error is handled
uniformly, including the schedule worker's.

## Design

### 1. Classify at the worker-loop edge

Add a small classification helper next to `handle_job_result`:

- `DomainError::ServiceUnavailable(_)` → **transient**, keep the retryable
  path (return the error → worker backs off → lease lapses → job reclaimed).
- `DomainError::Conflict(_)` → **not permanent**: a Conflict surfaces either a
  lost claim (the new owner is already redoing the work) or a lost
  concurrency permit (capacity was reclaimed; the job must be retried, not
  dead-lettered). Return the error as today.
- Everything else (`ValidationError`, `NotFound`, `VersionConflict`) →
  **permanent**: call `mark_failed(job.id, worker_id, &error.to_string(), false)`.

### 2. `handle_job_result` writes the terminal state

On a permanent error:

```rust
Err(error) if !is_transient(&error) && !matches!(error, DomainError::Conflict(_)) => {
    warn!(...);
    match deps.queue.mark_failed(job_id, worker_id, &error.to_string(), false).await {
        Ok(()) => Ok(()),
        // Already terminalized by the worker's own internal fail helper, or
        // reclaimed by another worker: nothing left to write.
        Err(DomainError::Conflict(_)) => Ok(()),
        Err(error) => Err(error),
    }
}
```

The `Conflict` from `mark_failed` is deliberately absorbed, not propagated:
`mark_failed` is owner-fenced (`WHERE id = $1 AND status = 'running' AND
worker_id = $2`), so a second mark on an already-terminal job or a mark on a
reclaimed job matches zero rows and returns `Conflict`. Both mean "the job is
already in its terminal state or owned by someone else" — the worker should
move on, not back off. Other `mark_failed` errors (e.g. DB outage) still
propagate so the loop backs off.

### 3. No changes to the worker internals

`ScriptImportWorker::fail` (internal marking of chunk-count / empty-input /
retry-chat errors) stays: `run_once`/`run_once_with_permit` rely on it, and
the edge's second `mark_failed` degenerates harmlessly into the absorbed
`Conflict` above. The double-write is exactly-once in effect because the SQL
WHERE clause makes the second update a no-op.

## Acceptance criteria (from the issue)

- [x] Classify processing errors into transient (retryable) vs. permanent
      (terminal) at the worker-loop edge (`handle_job_result`).
- [x] Call `mark_failed(job.id, worker_id, &error.to_string(), false)` for
      permanent errors so the job does not stay `running`.
- [x] Keep transient errors (`ServiceUnavailable`) on the retryable path.

## Out of scope

- `run_once` / `run_once_with_permit` (deterministic test / ad-hoc seams) keep
  their current behavior; the production loops route through
  `handle_job_result`.
- The retryable path itself (lease-lapse reclaim vs. `mark_failed(true)`
  backoff scheduling) is unchanged — transient errors behave exactly as
  before this change.
