<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: gemini-4-argon (google) -->

## 1. Core Domain & Port Definitions (`crates/core`)

- [x] 1.1 Add `AiImportStage` (`extracting_text`, `extracting`, `merging`, `storing_preview`) and `AiImportProgress` (`stage`, `chunk`, `chunks_total`, `episodes_seen`) to `crates/core/src/ai/views.rs` with `Serialize`, `Deserialize`, `ToSchema`, and add `#[serde(default)] pub progress: Option<AiImportProgress>` to `AiImportJob`.
- [x] 1.2 Add a pure display-label helper on `DraftEpisode` (`crates/core/src/ai/preview.rs`) that formats discovered episode markers as `"Ep. {number}"` (or trimmed `title` when `number` is absent) and deduplicates `episodes_seen` in first-seen order across chunks/scenes, with unit tests in `preview_tests.rs` and `views_tests.rs`.
- [x] 1.3 Extend `AiImportQueue` in `crates/core/src/ai/ports.rs` with `mark_progress(&self, id: AiImportJobId, worker_id: &str, progress: &AiImportProgress) -> Result<(), DomainError>` and storage-agnostic `subscribe(&self, id: AiImportJobId) -> Pin<Box<dyn Stream<Item = AiImportJobId> + Send>>` (both with default implementations so existing fakes keep compiling).

## 2. Infrastructure — Migration, Fenced Progress Writes & Event Hub (`crates/infra`)

- [x] 2.1 Add migration `20261012000001_ai_import_job_progress.{up,down}.sql` under `crates/infra/migrations/` adding nullable `progress JSONB` to `ai_import.ai_import_job`.
- [x] 2.2 Implement `AiJobEventHub` (`tokio::sync::broadcast` fan-out treating `RecvError::Lagged` as a synthetic wake-up) and the PostgreSQL `PgListener` bridge (`spawn_pg_job_event_listener` on channel `ai_import_job_events`) in `crates/infra/src/ai/`, preserving direct in-process `hub.notify(id)` publication for in-memory test queues and future SQLite operating mode.
- [x] 2.3 Implement owner-fenced `mark_progress` (`WHERE id = $1 AND status = 'running' AND claimed_by = $2`) in `PgAiImportQueue` (`crates/infra/src/ai/queue.rs`), reset `progress = NULL` on `claim_next*`, decode `progress` in `map_job_row`, and emit `pg_notify('ai_import_job_events', id::text)` + `hub.notify(id)` across all fenced lifecycle and progress transitions.
- [x] 2.4 Wire throttled `mark_progress` calls into `ScriptImportWorker`, `ScheduleImportWorker`, and `QueueMergeWorker` (`crates/infra/src/ai/workers.rs`, `merge_worker.rs`) at stage boundaries and after each completed chunk (never per LLM token), and add unit/integration tests for progress persistence, `episodes_seen` accumulation, owner-fence conflict rejection, and retry progress reset.

## 3. API — SSE Endpoint & OpenAPI Contract (`crates/api`)

- [x] 3.1 Implement `GET /v1/ai-import/jobs/{id}/events` (`stream_ai_import_job_events` in `crates/api/src/handlers/mod.rs`) using `axum::response::sse::Sse` with `Cache-Control: no-store, no-transform` and `X-Accel-Buffering: no`: enforce `ai_import_enabled`, job existence (`404 ai-import.not-found`), and `// AUTHZ-GATE: authorize_ai_job(&state, &current_user, &job, Action::Read)` (`403 ai-import.forbidden`); subscribe before reading the initial snapshot; emit `event: job` (`AiImportJobResponse`) with `id` watermark on initial connect and `Last-Event-ID` reconnect; send 30 s keep-alive comments; close stream immediately on terminal `JobStatus`.
- [x] 3.2 Register `stream_ai_import_job_events`, `AiImportProgress`, and `AiImportStage` in `crates/api/src/lib.rs`, wire `spawn_pg_job_event_listener` in `crates/api/src/main.rs` when AI import is enabled, and regenerate `backend/openapi.yaml` (`UPDATE_OPENAPI=1 cargo test -p api --test contract openapi_drift`).
- [x] 3.3 Add API handler tests in `crates/api/tests/` covering SSE snapshot-first delivery, `Last-Event-ID` resume, live progress/status frame push, terminal auto-close, and `403`/`404` `AUTHZ-GATE` rejections before stream open.

## 4. Flutter Client — Pinned-TLS SSE, Battery Contract & Progress UI (`frontend-flutter/`)

- [x] 4.1 Regenerate `vendor/breakdown_api/` via `bash scripts/regen-client.sh` and extend the Drift `AiImportJobsCache` table/DAO (`lib/data/cache/ai_import_cache.dart`, `ai_import_jobs_cache_dao.dart`, `cache_database.dart`) to persist and restore `progress`.
- [x] 4.2 Add an SSE line parser and update `AiImportRepository.watch(jobId)` (`lib/data/ai_import_repository.dart` + `lib/src/network/`) to stream `GET /v1/ai-import/jobs/{id}/events` with `ResponseType.stream` and a 65 s read-idle watchdog (`receiveTimeout`) over the existing ADR-024/032 pinned-CA `Dio` client, supporting `Last-Event-ID` on bounded reconnects and upserting received job snapshots into Drift.
- [x] 4.3 Update `AiJobStatusController` (`lib/features/ai_import/import_jobs/job_status_controller.dart`) to enforce the battery contract: cancel the SSE subscription immediately on screen disposal or app backgrounding (`paused`/`hidden`/`detached`), and on app foreground `resumed` perform one `getJobAndCache(jobId)` snapshot GET and re-subscribe only if the job is non-terminal; keep `AiImportJobsViewController` at zero `watch` calls.
- [x] 4.4 Update `AiJobStatusScreen` (`job_status_screen.dart`), `AiImportJobsScreen` (`jobs_screen.dart`), `lib/l10n/app_{de,en}.arb`, and `docs/design/screens/ai-import-jobs.md` to render localized `stage` copy, `chunk / chunks_total` progress, and `episodes_seen` chips/summary, with unit, widget, and golden tests.

## 5. Verification & Version Bumps

- [x] 5.1 Bump crate versions (`core` MINOR, `infra` MINOR, `api` MINOR) and `frontend-flutter/pubspec.yaml` in lockstep, and update `backend/CHANGELOG.md` and `frontend-flutter/CHANGELOG.md`.
- [ ] 5.2 Run `cargo test`, `cargo clippy --workspace --all-targets -- -D warnings`, `UPDATE_OPENAPI=1 cargo test -p api --test contract openapi_drift`, `dart format --set-exit-if-changed`, `flutter analyze`, `breakdown_lints_runner`, and `flutter test`.
