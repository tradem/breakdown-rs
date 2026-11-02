<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

# 800 — The apply-run progress slot gets a run identity and a liveness signal

## Why

Issue #800 (follow-up to #762 / PR #798). The apply-run progress slot
(`ai_import.ai_import_job.apply_progress`) is keyed by **job id only** and
carries no guarantee that a live run is visible. Four CodeRabbit findings on
PR #798 are symptoms of that one gap:

1. **No per-run identity** (`infra/src/ai/queue.rs`). Two accepted applies of
   one `succeeded` job overwrite each other's counters, and the first run to
   finish clears the slot — ending a still-live run's stream early.
2. **A run that starts and clears between two reads emits no end frame**
   (`api/src/handlers/mod.rs`, `classify_apply_run`). `sse_apply_stream` infers
   "a run happened" from payloads it *emitted*; a faster-than-one-tick run
   leaves `saw_run = false`, so the stream closes after
   `SSE_APPLY_IDLE_TICKS` **without** the documented final `null` frame. The
   client then reads a dropped connection and surfaces
   `ai_import.watch_exhausted`.
3. **Staleness is judged from the last progress write** (`core/src/ai/views.rs`).
   `ApplyProgress::is_stale_at` uses `STALE_AFTER` (10 min) on `updated_at`,
   which the worker writes per completed row — so one row slower than 10
   minutes makes the stream declare a **live** run finished.
4. **A client disconnect leaves the last payload behind**
   (`infra/src/ai/workers.rs`). Hyper drops the in-flight handler future, the
   worker stops, and the last `Applying` payload keeps reading as `Running`
   until `STALE_AFTER`. A run-scoped `Drop` guard cannot be written against a
   job-id-only clear (it could remove a **newer** run's progress).

## Decision (agreed 2026-11-04, see issue #800 "Open decision")

**A second apply of a `succeeded` job is rejected** with the registered
`409 ai-import.apply-in-flight` under an atomic single-flight claim.

* Release path: a claim is verifiably dead when its payload is older than
  `ApplyProgress::STALE_AFTER`; the next apply steals it inside the same
  conditional `UPDATE` (the cutoff is computed in Rust from `STALE_AFTER`, so
  the window has exactly one definition).
* The client treats that `409` as "a run is live, keep waiting" — it does not
  map it to the blocking `ApplyBlocked` branch (an ambiguous-timeout
  reconciliation retry legitimately hits it while the first POST still runs).

**UI consequence (same change):** the job view gains an additive
`applied: bool` (derived from the existing `accept_as_is` column — the job was
applied at least once), the jobs list renders a localized "already imported"
badge, and the apply button keeps working but only behind an explicit
"apply again" confirmation — the recovery path for an interrupted apply (the
server apply is idempotent, reserve-before-create) must not be removed.

## What

| Layer | Change |
|---|---|
| `core` | `ApplyRunId` (wire `run_id`, additive `serde(default)` on `ApplyProgress`); `AiImportJob.applied: bool`; `ApplyRunState { owner, seq, progress }`; port methods `claim_apply_run` + `apply_run_state`, `mark_apply_progress` takes the run identity; registry entry `ai-import.apply-in-flight`. |
| migration | `ai_import.ai_import_job.apply_run_id UUID` (the owning run, cleared with the payload) + `apply_run_seq BIGINT NOT NULL DEFAULT 0` (never cleared — the start/completion signal that survives a re-read). |
| `infra` | Ownership-conditioned claim write/clear; `apply_run_state` read; `ApplyWorker::apply_script` claims the slot, heartbeats the payload while a row is in flight (fixes #3), and holds a run-scoped `Drop` guard (fixes #4). |
| `api` | `classify_apply_run` classifies by the owning run **and** the seq delta since subscribe (fixes #2), so a superseded run's clear cannot end the current run's stream (fixes #1); `openapi.yaml` regenerated. |
| `frontend-flutter` | regenerated client; the apply-run boundary moves from `startedAt` to `runId`; `ai-import.apply-in-flight` is a wait-not-block outcome; "already imported" badge + re-apply confirmation. |

## Non-goals

- **The schedule apply path** (`ScheduleApplyWorker`) publishes no progress
  payload today and gets no claim: it has no progress slot to protect, and its
  double-dispatch is already idempotent. Documented, not silently implied.
- **Detaching the apply.** The `Drop` guard clears the run's *progress*; it
  never keeps the apply running after the client is gone — that is a separate
  product decision.
- **Lowering `STALE_AFTER`.** The heartbeat makes it a real
  "the process is gone" signal; the window itself is unchanged.

## Acceptance

- Two concurrent applies of one job cannot interleave their counters, and the
  first to finish cannot end the other's stream.
- A run that starts and clears inside one stream tick still produces the
  documented final `null` frame (seq delta since subscribe).
- A live run whose current row takes longer than `STALE_AFTER` is not
  classified as finished (heartbeat).
- A dropped client request clears its own run's payload and only its own.
- Deterministic tests: a paused/controlled clock for every timing bound
  (`backend/AGENTS.md` §4), no wall-clock gates.
