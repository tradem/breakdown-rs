<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: longcat-2.0-free (opencode) -->

# Proposal: Per-payload cleanup state for AI payload GC (Issue #206)

## Drift check

Issue #206 is a follow-up from the PR #204 review (comment 3736182636), filed
against the AI payload cleanup worker added in #198. Two things have landed
since, and both narrow the scope:

- **#181** already fixed *which* statuses are terminal (`failed` is excluded —
  it is the retryable backoff state) and added `payload_unavailable`. The
  retention predicate itself is correct and out of scope here.
- The `ai_import.ai_payload_cleanup` table does not exist in any form; no
  `cleanup_state` column, no marker, no handle-clearing. The finding is still
  fully valid.

What is **not** true is the review's framing that "missing objects count as
successful deletion" is part of the bug. That behaviour is correct and #181
depends on it — the fix must keep treating not-found as cleaned, and
additionally *mark* it, because a terminal job can never be re-claimed to
recreate its payload.

## Problem

`TERMINAL_JOBS_SQL` selected the oldest `batch_size` terminal jobs older than
the retention window, with no completion state anywhere. Deletions are
idempotent, so nothing was corrupted — which is exactly why no existing test
caught it. The damage was operational:

1. Every sweep re-paid the S3 round-trips for jobs it had already emptied.
2. `projection_ai_payload_gc_run` re-counted the same deletions on every run,
   so the counters describe scan volume, not work done — useless for alerting.
3. The oldest `batch_size` jobs are selected *forever*, so with more than
   `batch_size` retained terminal jobs, everything behind that parked head
   never gets swept at all. Retention silently stops being enforced.

(3) is the real defect: the `LIMIT` is meant to be a rate limit, and without a
completion mark it is a permanent horizon.

## Decision

A separate `ai_import.ai_payload_cleanup` table keyed `(job_id, payload_kind)`,
rather than a `cleanup_state` column on `ai_import_job`.

**Why not one column.** A job owns two independent payloads: `source_handle`
(NOT NULL, written at enqueue) and `preview_handle` (nullable, written only by
`mark_succeeded`). A partial sweep — source deleted, preview 503 — must retry
exactly the half that failed. A single flag cannot express that; it would
either block the source mark on the preview or abandon the preview silently.

**Why not two columns.** Two nullable timestamps on `ai_import_job` would work,
but that row is the hot queue record touched by every claim, lease renewal and
telemetry write. Retention is a cold concern and does not belong there.

**Why a row is the right shape.** The mark is an audit record, not job state:
it names the handle that was actually deleted and the sweep that deleted it,
which is what an operator needs when reconciling Garage against the queue.

## What may be marked

The invariant that makes this safe: **a mark is only ever written for a
deletion that actually happened.**

| Outcome | Marked? | Why |
|---|---|---|
| Deleted | yes | The object is gone. |
| Not found | yes | Goal state holds. A terminal job cannot be re-claimed, so no later write can recreate the payload — without a mark the sweep re-probes a permanently absent object forever. |
| Failed | **no** | The object is still there; the next sweep must retry it. |
| Dry run | **no** | Nothing was deleted. A mark would hide the payload from every *real* sweep, turning the observation mode into a permanent leak of the objects it was meant to report. |

Marks are flushed **before** the run-history row and **before** the early
return on the first deletion error, so one failure cannot discard the marks its
siblings in the same batch earned.

`updated_at` on the job row is deliberately never touched by a sweep: it is
both the retention clock and the sweep's `ORDER BY` key, so marking there would
reset the very window it measures.

## Port dependency (incidental but required)

`run_gc_sweep`, `spawn_gc_scheduler` and the new `delete_payload` helper became
generic over `AiPreviewStore + AiDocumentStore` instead of taking the concrete
`OpenDalAiPayloadStorage`. This is the port dependency hexagonal architecture
asks for, and it is load-bearing for the tests: Garage accepts every malformed
key (empty, 1500 bytes, control characters) and answers a delete of a
nonexistent object with success, so a *per-handle* deletion failure cannot be
produced through the real adapter. Pointing the whole sweep at an unreachable
endpoint fails every job in the batch and so cannot produce the mixed batch the
flush-ordering test needs.

Call sites are unchanged — `OpenDalAiPayloadStorage` implements both traits.

## Performance

The sweep had no usable index: `idx_ai_import_job_claim (status,
next_attempt_at, created_at)` cannot serve `updated_at` ordering, so it fell
back to a full table scan. That was tolerable only while it re-read the same
parked head; now that marks let it advance, `20260813000002` adds a partial
`(updated_at) WHERE status IN (terminal)` index, built `CONCURRENTLY`.

Measured at 200k terminal jobs with 150k marks, a full 1000-row batch plans as
an index scan with hashed anti-join probes at **~85 ms**. The cost grows
linearly with retained terminal *job* rows, because the scan still walks the
already-cleaned prefix in `updated_at` order before reaching the frontier. For
an hourly sweep this is far below the S3 round-trips the change removes. If job
rows are ever retained into the millions, the fix is to prune terminal job rows,
not to widen the index.

## Tests

`crates/integration-tests/tests/ai_payload_gc_cleanup_state.rs` (8 tests).
Retention policy stays in `ai_payload_restart_recovery.rs`; this file asserts
only progress and marking:

- A fully cleaned job is never selected again *(the headline regression)*.
- A partially cleaned job is re-selected for the missing payload only, and the
  already-cleaned one is not re-counted.
- A job with no preview is complete once its source is marked (a NULL
  `preview_handle` is not an outstanding payload — requiring a preview mark
  would park it in the candidate set forever).
- A dry run records no marks, and the job is still visible to the next sweep.
- A failed deletion records no mark and is retried.
- A successful Garage round-trip marks both payloads, the bytes are gone, and
  the second sweep scans 0.
- A not-found payload counts as cleaned and is marked.
- A partial batch persists the marks it earned even though the run returns an
  error.

Postgres-only where only the selection predicate is under test; real Garage
where a real deletion result is what the mark is derived from. All timing-safe:
ages come from backdating `updated_at` in SQL by 30 days against a 1-day
window, never from sleeping.

Plus 4 unit tests in `payload_cleanup.rs` covering the `UNNEST` column
alignment, the `payload_kind` constants against the migration's CHECK
constraint, the anti-join's presence in the SQL, and the non-markable dry-run
outcome.

## Version bumps

| Crate | Previous | New | Bump type | Reason |
|---|---|---|---|---|
| `infra` | 0.12.0 | 0.12.0 | none | 0.12.0 is already `Unreleased`; this change is additive within it and the generic signatures are source-compatible for all call sites. |
| `core` | 0.7.0 | 0.7.0 | none | No domain change — retention is infrastructure. |
| `api` | 0.6.1 | 0.6.1 | none | No source change; `spawn_gc_scheduler` still resolves with the same argument. |
