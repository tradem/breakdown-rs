<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4-flash (opencode-go) -->

# Proposal: Full lifecycle integration tests for AI payload storage (Issue #202)

## Drift check

Issue #202 is a follow-up from the PR #200 review (comment 3735128884). The
reviewer found that `ai_payload_storage_round_trip.rs` only exercised the
storage **port contract** — direct `put`/`get`/`delete` calls — and never
drove the production chain: upload handling, queue persistence, worker source
reload, preview retrieval, or apply after a simulated API restart.

What has landed since the issue was filed:

- **#181 / #217** defined restart-recovery semantics and added
  `ai_payload_restart_recovery.rs` — but that file tests **queue/job
  lifecycle** (`status`, `worker_id`, `lease`, GC), not the durable payload
  chain through the workers.
- `ai_import_permit_reconciliation.rs` drives `ScheduleImportWorker::run_once`
  against a real `PgAiImportQueue`, but with an in-memory
  `MemoryAiPreviewStore` and a raw-SQL-seeded job — it neither persists the
  source through the upload/enqueue command interface nor reloads it from
  durable storage.

The gap from the review comment is still fully open: no integration test
persists a source payload through the command interface, recreates the storage
wiring, reloads the source from durable storage after the "restart", retrieves
the preview through the production preview-store interface, or applies the
preview through the production `ApplyWorker`/event-store chain.

**Scope decision:** the script-import path requires the `pdftotext` subprocess
(not installed in the `integration-tests.yml` runner) and an LLM client. The
schedule-import path in native-CSV mode is fully deterministic — the CSV is
parsed in-process (`csv_schedule::parse_schedule_csv`), no subprocess, no LLM
call. The lifecycle test therefore drives the **schedule worker in native-CSV
mode** (mirroring `ai_import_permit_reconciliation.rs`), and the apply test
drives **`ApplyWorker::apply_script`** (one `CreateScene` through the real
`SceneCommandsImpl` → SierraDB → scene projector → projection), with the
preview seeded through the production `AiPreviewStore::put` +
`mark_succeeded` interfaces.

## Problem

The existing tests in `ai_payload_storage_round_trip.rs` verify that bytes
round-trip through Garage. They do not prove the operational promises of issue
#174 / #181:

1. that an uploaded source document survives an API restart and is reloaded
   by a fresh worker from durable storage;
2. that a preview produced after the restart is retrievable through the same
   production `AiPreviewStore` interface the `get_ai_import_preview` handler
   uses;
3. that applying a preview drives the real command → event → event-store →
   projector → projection chain (the "Tier-4" pattern from
   `sierradb_round_trip.rs`).

## Required changes

### 1. `crates/integration-tests/tests/ai_payload_storage_round_trip.rs` (extend)

Add two tests plus shared helpers:

**`ai_payload_storage_lifecycle_survives_restart`** (Postgres + Garage;
deterministic — no `pdftotext`, no LLM):

1. **Upload through the command interface** — the exact shape of the API
   handler `enqueue_ai_upload`: `AiDocumentStore::put_source` for the CSV
   bytes, then `PgAiImportQueue::enqueue` with the returned `source_handle`
   (schedule kind, CSV format).
2. **Queue persistence** — `PgAiImportQueue::get` returns the job row with
   the persisted `source_handle`, `Pending` status, kind and format.
3. **Simulated restart** — rebuild the storage wiring: a *fresh*
   `OpenDalAiPayloadStorage` instance (same bucket) and a *fresh*
   `PgAiImportQueue` (same pool). Assert the source reloads through the new
   wiring.
4. **Worker source reload** — `ScheduleImportWorker::run_once` (native-CSV
   mode, `UnusedLlmClient` never called) claims the persisted job, reloads
   the bytes via `AiDocumentSource::load` from the restarted storage, parses
   them in-process, stores the preview, marks the job `Succeeded`.
5. **Bounded eventual-consistency retries** — `await_job_status` polls for
   the async status flip within a deadline (same `PROJECTION_DEADLINE` /
   `POLL_INTERVAL` constants as `sierradb_round_trip.rs`).
6. **Preview retrieval through production interfaces** — a third storage
   instance reads `preview_handle` via `AiPreviewStore::get`; the payload
   decodes as the expected `ShootingSchedule` (rows, labels, dates).
7. A second `run_once` returns `Ok(false)` — the terminal state persisted and
   the job is not re-processed.

**`ai_payload_apply_round_trips_through_projection`** (Postgres + SierraDB +
Garage):

1. Upload + enqueue a **script** job through the production queue interface.
2. Produce the preview through the production `AiPreviewStore::put`
   (JSON `ScriptContext`), then complete the job through the production
   queue lifecycle (`claim_next_kind` + `mark_succeeded` — owner-fenced).
3. **Simulated restart** — fresh storage + fresh queue + fresh mapping repo;
   reload the preview from the restarted wiring.
4. **Apply through production interfaces** — `ApplyWorker::apply_script`
   with the real `SceneCommandsImpl` (event store), real
   `PgAiImportMappingRepository`, real `PgAiImportQueue` and a `Create`
   decision.
5. **Command → event → event-store → projector → projection** — the scene
   projector is running; `await_scene_projection` polls
   `SceneRepositoryImpl::find_by_id` (bounded retries, retry on `NotFound`)
   and asserts the projected `SceneView` matches the preview details.

### 2. `.github/workflows/integration-tests.yml`

`ai_payload_storage_round_trip` is currently not run in CI at all. Add the
test file to the **SierraDB round-trip (sequential)** group: one of the two
new tests requires SierraDB, and the sequential group already runs the
Garage + SierraDB photo round-trip files. The storage-contract tests already
present in the file run in the same group without harm.

## Non-goals

- No production code changes. This is a test-only change; no crate version
  bump.
- The script-import worker path (PDF extraction + LLM) is **not** driven in
  these tests: it needs `pdftotext` (absent on the `integration-tests.yml`
  runner) and a live LLM. It remains covered by the infra unit tests
  (`process_text` seam) and the nightly LLM smoke test.
- Not adding the other existing AI payload/queue test files
  (`ai_payload_restart_recovery`, `ai_import_*`, …) to CI — that is a
  pre-existing gap, out of scope here.

## Test structure

- Reuse `crate::fixtures::{spawn_postgres, spawn_sierradb, spawn_garage}`.
- Copy the bounded-retry pattern (`PROJECTION_DEADLINE`, `POLL_INTERVAL`,
  retry-on-`NotFound`) from `sierradb_round_trip.rs`.
- `UnusedLlmClient` (must never be called in native-CSV mode) copied from
  `ai_import_permit_reconciliation.rs`.

## Acceptance criteria

- [x] Test persists source payload through the command interface
- [x] Test simulates restart by recreating storage wiring
- [x] Test verifies worker can reload source payload after restart
- [x] Test verifies preview retrieval after restart
- [x] Test uses bounded retries for eventual consistency
- [x] Tests are deterministic (no wall-clock timing dependencies)
