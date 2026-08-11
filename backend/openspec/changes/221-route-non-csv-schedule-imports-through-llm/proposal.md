<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4-flash (opencode-go) -->

# 221 — Route non-CSV schedule import jobs through the LLM path

## Summary

`ScheduleImportWorker::process` is called with `native_csv=true` in both
branches of `schedule_worker_tick` (`worker_loop.rs`), so non-CSV schedule
uploads never reach the LLM extraction path. This change persists the declared
source format on the job at the API edge, derives the extraction path from it
in the worker loop, and adds PDF text extraction so `application/pdf` schedule
uploads (an advertised content type) work end-to-end.

## Problem

- Schedule jobs do not persist the upload format; the worker cannot
  distinguish CSV from non-CSV uploads at processing time.
- Both branches of `worker_loop.rs` pass `true` to `ScheduleImportWorker::process`.
- Even if routed, the non-CSV path does `String::from_utf8(bytes)` and would
  reject a PDF schedule ("not UTF-8 text"), so PDF schedules could never work.

## Decisions

- **`SourceFormat` enum in core** (`Csv | Pdf | PlainText`) — faithful to the
  content types accepted by `POST /ai-import/schedules`; `uses_native_csv()`
  is the only routing predicate the worker needs.
- **Persist on the job**: `AiImportEnqueueRequest.source_format` +
  `AiImportJob.source_format` + a NOT NULL `source_format` column on
  `ai_import.ai_import_job` (backfilled: legacy schedule rows → `csv`,
  script rows → `pdf`).
- **Derive in the worker loop** (issue #221): `native_csv` is dropped from
  `process`/`run_once`/`run_once_with_permit`; the extraction path is derived
  from `job.source_format`, removing the caller/callee disagreement entirely.
- **PDF extraction in the schedule LLM path**: `ScheduleImportWorker` gains a
  bounded `PdfTextExtractor` (same pattern as `ScriptImportWorker`); `Pdf`
  sources are extracted to text before the LLM call, `PlainText` sources pass
  through as UTF-8.

## Acceptance Criteria

- [x] Persist the source document format (CSV vs. non-CSV) on the job.
- [x] Route non-CSV schedule jobs through the LLM extraction path in `worker_loop.rs`.
- [x] Keep CSV schedule jobs on the native parser path.
- [x] PDF schedule uploads work end-to-end (PDF → text → LLM).

## Impact

- `crates/core/src/ai/views.rs` — `SourceFormat` enum, `AiImportJob.source_format`.
- `crates/core/src/ai/ports.rs` — `AiImportEnqueueRequest.source_format`.
- `crates/core/src/ai/mod.rs` — re-export `SourceFormat`.
- `crates/infra/migrations/20260814000001_ai_import_source_format.{up,down}.sql` — new column.
- `crates/infra/src/ai/queue.rs` — INSERT + row mapping + parser.
- `crates/infra/src/ai/workers.rs` — `ScheduleImportWorker.extractor`, derived path.
- `crates/infra/src/ai/worker_loop.rs` — both branches derive from the job.
- `crates/api/src/handlers/mod.rs` — content-type → `SourceFormat` at the edge.
- Tests: `payload_recovery_tests.rs`, `tests.rs`, `heartbeat.rs`,
  `ai_import_permit_reconciliation.rs`, `ai_import_queue_lease.rs`,
  `ai_import_queue_telemetry.rs`, `ai_payload_gc_cleanup_state.rs`,
  `ai_payload_restart_recovery.rs`.
