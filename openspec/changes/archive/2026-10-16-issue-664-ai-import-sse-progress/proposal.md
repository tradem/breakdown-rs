<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: gemini-4-argon (google) -->

## Why

AI import jobs currently give users almost no visibility while a screenplay or shooting schedule is being processed: the UI only shows a coarse `Pending | Running | Succeeded | Failed | DeadLetter | PayloadUnavailable` status without indicating *which* extraction stage is active, *how many* scene chunks have been processed, or *which* episodes (`Ep.: n`) have been discovered in the document so far. Furthermore, `AiImportRepository.watch` in the Flutter client relies on a 30-attempt backoff polling loop (`GET /v1/ai-import/jobs/{id}`), which causes unnecessary wakeups/requests, wastes battery on mobile devices, and still leaves progress opaque.

## What Changes

- **Additive `progress` payload on `AiImportJob` (`crates/core`, `crates/infra`):**
  - Introduce `AiImportProgress` (`stage: AiImportStage`, `chunk: Option<u32>`, `chunks_total: Option<u32>`, `episodes_seen: Vec<String>`) and `AiImportStage` (`extracting_text`, `extracting`, `merging`, `storing_preview`) in `breakdown_core::ai::views`, exposed as `#[serde(default)] pub progress: Option<AiImportProgress>` on `AiImportJob`.
  - Add migration `20261012000001_ai_import_job_progress` adding `progress JSONB` to `ai_import.ai_import_job`.
  - Add an owner-fenced, throttled `AiImportQueue::mark_progress(id, worker_id, progress)` method (`WHERE id = $1 AND status = 'running' AND claimed_by = $2`) called at stage boundaries and once per completed chunk (never per LLM token).
  - Populate `episodes_seen` at zero extra LLM cost from the existing deterministic `Ep.:` marker scan (`SceneChunk.episode`, issue #581) and per-chunk extracted `DraftScene.episode` metadata in first-seen order (e.g. `["Ep. 3", "Ep. 4"]`).
- **Hexagonal event distribution with PostgreSQL `NOTIFY` + SQLite portability (`crates/core`, `crates/infra`):**
  - Extend `AiImportQueue` (or a companion port in `breakdown_core::ai`) with a backend-agnostic per-job subscription stream (`subscribe(id: AiImportJobId)`) backed by an in-process `tokio::sync::broadcast` hub (`AiJobEventHub`).
  - In the PostgreSQL operating mode (`PgAiImportQueue`), fenced status and progress SQL statements emit `pg_notify('ai_import_job_events', ...)` in the same statement/transaction, and a single shared background `PgListener` task per API instance forwards cross-instance notifications into the local `AiJobEventHub` (using 1 connection per API node, never 1 per SSE client).
  - Preserve full portability for a future embedded/single-node **SQLite** read-model and operational-queue mode: because `core` and `api` depend only on the port subscription stream, a SQLite queue adapter publishes directly to the in-process `AiJobEventHub` on commit without requiring `LISTEN/NOTIFY`.
- **Server-Sent Events endpoint `GET /v1/ai-import/jobs/{id}/events` (`crates/api`):**
  - Serve `text/event-stream` via `axum::response::sse::Sse` gated by the existing authentication middleware and the handler-internal `// AUTHZ-GATE:` `authorize_ai_job(&state, &current_user, &job, Action::Read)` check (403 `ai-import.forbidden`, 404 `ai-import.not-found`).
  - Emit a full `AiImportJobResponse` snapshot as the first SSE event on every initial connect and `Last-Event-ID` reconnect (snapshot + deltas model, eliminating catch-up polling), send ~30 s keep-alive comment frames against reverse-proxy idle timeouts, and close the stream cleanly as soon as a terminal status (`succeeded`, `dead_letter`, `payload_unavailable`) is sent.
- **Flutter SSE subscription, battery contract, and stage/episode UI (`frontend-flutter/`):**
  - Switch `AiImportRepository.watch(jobId)` from periodic backoff polling to `GET /v1/ai-import/jobs/{id}/events` over the existing ADR-024/032 pinned-CA `Dio` instance (`ResponseType.stream` interceptor, preserving `SecurityContext(withTrustedRoots: false)`), with `Last-Event-ID` resume and a single snapshot `GET /v1/ai-import/jobs/{id}` on app lifecycle resume.
  - Enforce the **battery contract**: only `AiJobStatusScreen` opens an SSE stream while foregrounded and cancels it immediately on background/dispose; `AiImportJobsScreen` (#547) keeps its one-shot `GET /v1/ai-import/jobs` + manual pull-to-refresh (zero SSE streams) and renders the `progress` summary from the fetched rows.
  - Render localized stage copy, chunk counter (`chunk / chunks_total` with determinate progress bar when `chunks_total > 0`), and `episodes_seen` chips on `AiJobStatusScreen` (and compact stage/episode subtitle on `AiImportJobsScreen`).
- **Architecture Decision Record (`ADR-038`):**
  - Record the SSE push architecture, snapshot-first resume, Postgres `NOTIFY` + `PgListener` → `broadcast` hub with SQLite operating-mode seam, battery contract, and the explicit evaluation/rejection of HTTP/3 (non-goal due to ADR-024/032 CA-pinning interplay and TCP-only `hyper`), WebSockets, Webhooks, and periodic polling.

## Capabilities

### New Capabilities
<!-- None — extends existing capabilities -->

### Modified Capabilities
- `ai-import`: Add `progress` field (`stage`, `chunk`, `chunks_total`, `episodes_seen`) to `AiImportJob`, owner-fenced throttled `mark_progress` queue writes, storage-agnostic job event publication (`pg_notify` + shared `PgListener` → `broadcast` in PG mode; direct `broadcast` in test/future SQLite mode), and `GET /v1/ai-import/jobs/{id}/events` SSE endpoint (snapshot-first, `Last-Event-ID` resume, `AUTHZ-GATE`, keep-alive, terminal close).
- `flutter-ai-import-workflow`: Replace periodic backoff polling on `AiJobStatusScreen` with foreground-only SSE over the pinned-CA `Dio` client + single snapshot GET on app resume (battery contract), keep `AiImportJobsScreen` watch-free (one-shot GET + pull-to-refresh), and render extraction stage, chunk progress, and `episodes_seen` in the import UI.

## Impact

- **Backend crates:** `crates/core` (`ai::views`, `ai::ports`), `crates/infra` (`ai::queue`, `ai::workers`, `ai::merge_worker`, `ai::events` hub/listener, migration `20261012000001_ai_import_job_progress`), `crates/api` (`handlers::stream_ai_import_job_events`, `openapi.yaml`).
- **Frontend (`frontend-flutter/`):** Regenerated `vendor/breakdown_api/`, `lib/src/network/` SSE streaming interceptor, `lib/data/ai_import_repository.dart`, `lib/data/cache/` Drift schema migration for `progress`, `lib/features/ai_import/import_jobs/{job_status_controller,job_status_screen,jobs_screen}.dart`, and `lib/l10n/app_{de,en}.arb`.
- **Documentation & Governance:** `backend/docs/architecture/adrs/ADR-038-ai-import-sse-progress-and-event-hub.md`, `backend/docs/architecture/adrs/README.md`, `docs/design/screens/ai-import-jobs.md`.
