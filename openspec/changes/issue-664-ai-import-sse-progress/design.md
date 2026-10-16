<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: gemini-4-argon (google) -->

## Context

Today, `AiImportJob` exposes only coarse operational lifecycle states (`pending`, `running`, `succeeded`, `failed`, `dead_letter`, `payload_unavailable`) plus retry/attempt failure history (issues #637/#639). While a multi-chunk screenplay (up to 128 chunks × 120 s timeout) or schedule is being extracted, the user sees an indeterminate spinner with zero insight into:

1. **Where processing currently is** (PDF text extraction, chunk `k` of `N` LLM extraction, deterministic schedule-to-scene merge, or preview storage).
2. **Which episodes the document contains** (`Ep.: 3 (Titel)` markers, which `extract_scenes` in `crates/core/src/ai/preview.rs` already parses deterministically before the first LLM request).

On the client side, `AiImportRepository.watch(jobId)` (`frontend-flutter/lib/data/ai_import_repository.dart`) polls `GET /v1/ai-import/jobs/{id}` up to 30 times via `ExponentialBackoffScheduler`. Periodic polling wakes the radio repeatedly, wastes battery, adds backoff latency as the import progresses, and exhausts after 30 ticks on long scripts (`ai_import.watch_exhausted`).

At the same time, our architecture has strict non-negotiable constraints:
- **CQRS boundary (`AGENTS.md` §1):** `AiImportJob` is an operational queue row in `ai_import.ai_import_job`, not an event-sourced aggregate (ADR-030). Workers must never query domain read projections.
- **Owner-fenced worker writes (issue #177):** Every worker lifecycle write (`mark_running`, `mark_succeeded`, `mark_failed`, `record_worker_telemetry`) is fenced by `WHERE id = $1 AND status = 'running' AND claimed_by = $2` so a displaced worker whose lease lapsed cannot overwrite the new owner's state.
- **Handler-internal `AUTHZ-GATE` (`AGENTS.md` §3):** All `/v1/ai-import/jobs/*` routes sit under `Requirement::Authenticated` and must call `authorize_ai_job(&state, &current_user, &job, Action::Read)` inside the handler body before streaming any data.
- **Client CA pinning (ADR-024, ADR-032):** The Flutter client trusts only the bundled per-flavor root CA (`SecurityContext(withTrustedRoots: false)`). Any streaming transport must ride on the existing pinned `Dio` client (`buildPinnedDio`).
- **Multi-DB read/operational portability (PostgreSQL + future SQLite operating mode):** While production deployments run PostgreSQL (`PgAiImportQueue`), the architecture must keep a clean hexagonal seam so an embedded/single-node **SQLite** read-model and operational-queue mode can be added later without changing `core`, `api`, or the SSE protocol.

## Goals / Non-Goals

**Goals:**
- Introduce `GET /v1/ai-import/jobs/{id}/events` (`text/event-stream` via `axum::response::sse`) delivering snapshot-first, push-based job progress and lifecycle transitions.
- Extend `AiImportJob` with an additive `progress: Option<AiImportProgress>` field (`stage`, `chunk`, `chunks_total`, `episodes_seen`) persisted in `ai_import.ai_import_job.progress JSONB` via an owner-fenced, per-chunk throttled `mark_progress` method.
- Distribute job updates without database polling via a hexagonal `AiJobEventHub` (`tokio::sync::broadcast`) bridged in PostgreSQL mode by `pg_notify` + a single shared `PgListener` task per API instance, and directly usable in-process by test queues and a future SQLite operating mode.
- Replace periodic backoff polling in Flutter's `AiImportRepository.watch(jobId)` with a foreground-only SSE subscription over the pinned-CA `Dio` client, paired with a single snapshot `GET` on app resume.
- Surface current extraction stage, `chunk / chunks_total`, and discovered episode labels (`episodes_seen`) on `AiJobStatusScreen` (live via SSE) and `AiImportJobsScreen` (from its one-shot list fetch).

**Non-Goals:**
- **Webhooks:** Server-to-server push is unsuitable for mobile clients behind NAT/Doze and would require public device endpoints and wakeup power penalties.
- **Periodic client polling:** Replaced on `AiJobStatusScreen` by SSE + snapshot-on-resume; banned on `AiImportJobsScreen` (manual pull-to-refresh only).
- **Per-token LLM streaming:** Progress updates are throttled to stage transitions and completed chunks (`1..=chunks_total`), never per generated LLM token.
- **HTTP/3 (QUIC):** Explicitly dispositioned as a non-goal (see Decision D7).
- **WebSockets / GraphQL subscriptions / FCM push:** Unnecessary bidirectional or external push machinery; SSE is unidirectional HTTP and fits the exact problem.
- **Replacing the worker claim-poll loop:** The worker's `claim_next_kind_reconciling … FOR UPDATE SKIP LOCKED` loop remains the crash-safe correctness mechanism for job claiming.

## Architecture Overview

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                         BACKEND (Rust / Axum / Infra)                        │
│                                                                              │
│  ScriptImportWorker / ScheduleImportWorker / QueueMergeWorker                │
│       │                                                                      │
│       │ mark_running / mark_progress(per chunk) / mark_succeeded / ...       │
│       │ (owner-fenced: WHERE id = $1 AND status = 'running' AND claimed_by)  │
│       ▼                                                                      │
│  ┌────────────────────────────────────────────────────────────────────────┐  │
│  │ AiImportQueue Port (breakdown_core::ai::ports::AiImportQueue)          │  │
│  │  • mark_progress(id, worker_id, AiImportProgress)                      │  │
│  │  • subscribe(id) -> BoxStream<'static, AiImportJobId>                  │  │
│  └──────────────────┬──────────────────────────────────┬──────────────────┘  │
│                     │                                  │                     │
│        [PostgreSQL Operating Mode]        [In-Memory / Future SQLite Mode]   │
│                     │                                  │                     │
│                     ▼                                  ▼                     │
│  ┌─────────────────────────────────────┐  ┌────────────────────────────────┐ │
│  │ PgAiImportQueue                     │  │ SqliteAiImportQueue / Fake     │ │
│  │ UPDATE ai_import.ai_import_job ...  │  │ UPDATE ai_import_job ...       │ │
│  │ RETURNING ...,                      │  │ (commits in-process, then      │ │
│  │   pg_notify('ai_import_job_events', │  │  publishes job_id directly to  │ │
│  │             id::text)               │  │  AiJobEventHub)                │ │
│  └──────────────────┬──────────────────┘  └────────────────┬───────────────┘ │
│                     │                                      │                 │
│                     ▼ (1 PgListener per API node)          │                 │
│  ┌─────────────────────────────────────────────────────────┴───────────────┐ │
│  │ AiJobEventHub (in-process tokio::sync::broadcast<AiImportJobId>)        │ │
│  └──────────────────────────────────────┬──────────────────────────────────┘ │
│                                         │                                    │
│                                         ▼                                    │
│  GET /v1/ai-import/jobs/{id}/events (SSE Handler + // AUTHZ-GATE)            │
│   1. Load job via queue.get(id) + authorize_ai_job(..., Action::Read)        │
│   2. Subscribe to queue.subscribe(id) BEFORE initial snapshot read           │
│   3. Yield initial `event: job` snapshot (id: <updated_at_micros>)           │
│   4. If job.status.is_terminal() -> close stream immediately                 │
│   5. Loop: on hub signal (or broadcast lag) -> queue.get(id) -> yield        │
│            `event: job` if state/progress changed; close on terminal;        │
│            send `: keep-alive` comment every 30 s                            │
└─────────────────────────────────────────┬────────────────────────────────────┘
                                          │ HTTPS (Pinned Root CA, ADR-032)
                                          │ text/event-stream (HTTP/1.1 or h2)
                                          ▼
┌──────────────────────────────────────────────────────────────────────────────┐
│                      FLUTTER CLIENT (frontend-flutter/)                      │
│                                                                              │
│  AiJobStatusScreen (Foreground-Only Subscription — Battery Contract)         │
│   • Foregrounded: subscribes to repo.watch(jobId) -> Dio ResponseType.stream │
│   • Transient drop while foregrounded: reconnects with `Last-Event-ID`       │
│     (server always sends fresh full snapshot first -> zero missed state)     │
│   • App backgrounded / screen disposed: cancels stream subscription (0 wake) │
│   • App resumed to foreground: 1 snapshot GET + re-open SSE if non-terminal  │
└──────────────────────────────────────────────────────────────────────────────┘
```

## Decisions

### D1 — SSE Wire Protocol: Snapshot-First, Self-Contained `job` Events, `Last-Event-ID`, Terminal Close

**Decision:**
- Route: `GET /v1/ai-import/jobs/{id}/events` returning `200 OK` with `Content-Type: text/event-stream`, `Cache-Control: no-store, no-transform` (`no-transform` per RFC 9111 §5.2.2.4 instructs enterprise ADCs such as Citrix NetScaler / WAFs not to buffer or gzip-compress the stream), and `X-Accel-Buffering: no`.
- Authorization runs **before** opening the stream:
  - If `AI_IMPORT_ENABLED` is `false`, return `404 ai-import.disabled` (`application/problem+json`).
  - Fetch the job via `ai_import_queue().get(id)`; if missing, return `404 ai-import.not-found`.
  - Run `// AUTHZ-GATE: authorize_ai_job(&state, &current_user, &job, Action::Read).await?` (403 `ai-import.forbidden` on denial).
- **Race-free subscription order:** The handler subscribes to `ai_import_queue().subscribe(id)` *before* reading the snapshot emitted as the first frame (or re-reads after subscribing), ensuring no transition between the initial read and stream loop can be missed.
- **Snapshot + deltas via full `AiImportJobResponse` frames:** Because `AiImportJobResponse` (`{ "job": AiImportJob }`) is compact (~500–800 bytes including `progress` and `attempts`), every SSE data frame (`event: job`) carries the serialized `AiImportJobResponse` JSON and sets the SSE `id:` field to a monotonic watermark derived from the job row (e.g. `updated_at` in unix microseconds).
- **`Last-Event-ID` handling:** The handler accepts the optional `Last-Event-ID` request header (`HeaderMap`). Because the first frame on every connection or reconnection is always the current authoritative `AiImportJobResponse` snapshot from the queue, a reconnecting client immediately converges on the latest state without needing a separate catch-up poll or server-side event replay buffer.
- **Keep-alive & terminal closure:** `axum::response::sse::KeepAlive` emits a comment frame (`: keep-alive`) every 30 seconds to prevent reverse-proxy idle timeouts. Whenever the emitted snapshot has `job.status.is_terminal()` (`succeeded`, `dead_letter`, `payload_unavailable`), the stream yields that final `event: job` frame and terminates cleanly. Note that `failed` is *retryable* (`JobStatus::is_terminal()` is `false`), so the stream remains open across retry backoff windows unless the client leaves the screen.

### D2 — Progress Payload Shape (`AiImportProgress` & `AiImportStage`) and Zero-Token `episodes_seen`

**Decision:**
Add two types to `breakdown_core::ai::views` (re-exported in `breakdown_core::ai` and registered in `utoipa` OpenAPI schemas):

```rust
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "snake_case")]
pub enum AiImportStage {
    /// Extracting text from PDF and scanning deterministic scene/episode markers.
    ExtractingText,
    /// Running per-chunk LLM or CSV extraction.
    Extracting,
    /// Running deterministic schedule-to-scene merge.
    Merging,
    /// Writing the extracted preview payload to durable object storage.
    StoringPreview,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
pub struct AiImportProgress {
    pub stage: AiImportStage,
    /// 1-based index of the chunk currently being processed or just completed.
    #[serde(default)]
    pub chunk: Option<u32>,
    /// Total chunks in the document (known once chunking finishes).
    #[serde(default)]
    pub chunks_total: Option<u32>,
    /// Human-readable episode labels discovered so far, in first-seen order
    /// (e.g. `["Ep. 3", "Ep. 4"]`), deduplicated.
    #[serde(default)]
    pub episodes_seen: Vec<String>,
}
```

And extend `AiImportJob`:
```rust
#[serde(default)]
pub progress: Option<AiImportProgress>,
```

- **How `episodes_seen` is computed:** `SceneChunk` (`crates/core/src/ai/preview.rs`) already carries `episode: Option<DraftEpisode>` from the deterministic `Ep.: <n> (<Titel>)` scanner (#581), and each LLM-extracted `DraftScene` may also carry an `episode: Option<DraftEpisode>` fallback. A pure helper on `DraftEpisode` formats the compact label (`"Ep. {number}"` when `number` is `Some(n)`, else the trimmed `title` when present) and accumulates distinct labels in first-seen order as chunks are scanned and processed. This costs zero extra LLM tokens and never leaks NDA script prose.
- **Database representation:** Migration `20261012000001_ai_import_job_progress` adds `progress JSONB` (nullable, default `NULL`) to `ai_import.ai_import_job`.

### D3 — Owner-Fenced, Throttled `AiImportQueue::mark_progress`

**Decision:**
- Add `async fn mark_progress(&self, id: AiImportJobId, worker_id: &str, progress: &AiImportProgress) -> Result<(), DomainError>` to `AiImportQueue` (with a default no-op implementation `Ok(())` so existing unit-test fakes that do not assert on progress keep compiling without boilerplate).
- **Owner fence:** In `PgAiImportQueue`, `mark_progress` executes:
  ```sql
  UPDATE ai_import.ai_import_job
  SET progress = $3,
      updated_at = now()
  WHERE id = $1
    AND status = 'running'
    AND claimed_by = $2
  ```
  and passes `rows_affected` through `ensure_claim_owned(rows_affected, id, worker_id, "mark_progress")`. If a worker's lease expired and another worker reclaimed the job, `mark_progress` returns `DomainError::Conflict` and the displaced worker aborts immediately before making another billable LLM call.
- **Throttling (publish points):**
  - `ScriptImportWorker`:
    1. After PDF extraction + `extract_scenes` validation: `stage = Extracting`, `chunk = Some(0)`, `chunks_total = Some(chunk_count)`, `episodes_seen` seeded from the first chunk's deterministic marker (if any).
    2. After each chunk `i` (`1..=chunk_count`) completes `retry_chat`: `stage = Extracting`, `chunk = Some(i)`, `chunks_total = Some(chunk_count)`, `episodes_seen` updated with any episode markers seen up through chunk `i`.
    3. Before `previews.put`: `stage = StoringPreview`, `chunk = Some(chunk_count)`, `chunks_total = Some(chunk_count)`.
  - `ScheduleImportWorker`:
    1. On start of extraction: `stage = ExtractingText` (for PDF) or `stage = Extracting` (`chunk = Some(0)`, `chunks_total = Some(1)`).
    2. Before `previews.put`: `stage = StoringPreview`, `chunk = Some(1)`, `chunks_total = Some(1)`.
  - `QueueMergeWorker`:
    1. On claim/start: `stage = Merging`.
    2. Before `previews.put`: `stage = StoringPreview`.
  - When a job is re-claimed after a retryable `failed` attempt (`claim_next*`), `progress` is reset to `NULL` in the claim SQL statement so stale progress from a previous attempt never flashes before the new attempt's first `mark_progress`.

### D4 — Hexagonal Event Distribution: In-Process `AiJobEventHub` + Postgres `pg_notify`/`PgListener` Bridge + SQLite Portability

**Decision:**
- **Why not per-SSE-client `PgListener`?** Opening a dedicated PostgreSQL connection (`PgListener::connect_with(&pool)`) for every open SSE stream would tie up one pool connection per watching user and allow concurrent watchers to starve transactional queries.
- **Why not Postgres-only in `api`?** We want to preserve the ability to run Breakdown RS in a future single-node/embedded operating mode backed by **SQLite** for the read model and operational queues (which has no cross-process `LISTEN/NOTIFY`).
- **The hexagonal solution:**
  1. `AiImportQueue` in `crates/core/src/ai/ports.rs` exposes:
     ```rust
     fn subscribe(&self, _id: AiImportJobId) -> BoxStream<'static, AiImportJobId> {
         Box::pin(futures::stream::empty())
     }
     ```
     (returning a stream of wake-up notifications filtered to `id`).
  2. `crates/infra/src/ai/` provides `AiJobEventHub`, a lightweight wrapper around `tokio::sync::broadcast::Sender<AiImportJobId>` (capacity e.g. 256).
     - Calling `hub. notify(job_id)` is non-blocking and infallible (if zero SSE clients are currently listening, the send is a no-op).
     - Calling `hub.subscribe(job_id)` returns a `Stream<Item = AiImportJobId>` that yields whenever `job_id` is notified **or** when the broadcast receiver reports `RecvError::Lagged(_)` (treating lag as a synthetic wake-up so the SSE handler simply re-reads the latest `AiImportJob` row from the queue!).
  3. **In-process publication (works for PostgreSQL, in-memory fakes, and future SQLite):** Every queue write method that changes job state or progress (`enqueue` when returning an existing or new job, `claim_next*`, `release_claim`, `mark_running`, `mark_progress`, `mark_succeeded`, `mark_failed`, `mark_payload_unavailable`) calls `self.hub.notify(id)` right after the SQL statement commits.
  4. **PostgreSQL cross-instance bridge (`pg_notify` + single `PgListener`):**
     - In `PgAiImportQueue`, the fenced `UPDATE` statements (`claim_next*`, `release_claim`, `mark_running`, `mark_progress`, `mark_succeeded`, `mark_failed`, `mark_payload_unavailable`) include `pg_notify('ai_import_job_events', id::text)` inside the SQL statement (e.g. via `RETURNING pg_notify('ai_import_job_events', id::text)`), so a notification is emitted atomically by PostgreSQL if and only if the transaction commits and affects the row, with a tiny 36-byte UUID payload well below PostgreSQL's 8000-byte `NOTIFY` ceiling.
     - A single background task per API process (`spawn_pg_job_event_listener(pool, hub, shutdown)`) listens on channel `ai_import_job_events` via `sqlx::postgres::PgListener`, parses the UUID payload, and calls `hub.notify(job_id)`. If the listener connection drops transiently, it reconnects with bounded backoff and logs via `tracing::warn!`.
     - Because the SSE handler compares the newly fetched `AiImportJob` watermark (`updated_at` + `status` + `progress`) against the last emitted frame, duplicate notifications (e.g. local `hub.notify` + echoed `pg_notify` on the same node) are deduplicated cleanly and never emit duplicate SSE frames.
  5. **Future SQLite operating-mode compatibility:** When a `SqliteAiImportQueue` adapter is introduced later, it holds the exact same `AiJobEventHub` and calls `self.hub.notify(id)` after its SQLite write commits. Neither `crates/core`, `crates/api`, nor the Flutter client changes by a single line.

### D5 — Flutter Battery Contract & Subscription Lifecycle

**Decision:**
- **Single SSE consumer (`AiJobStatusScreen` only):**
  - `AiJobStatusScreen` (via `AiJobStatusController`, `@Riverpod(keepAlive: false)`) is the **only** surface that calls `AiImportRepository.watch(jobId)`.
  - Leaving `AiJobStatusScreen` disposes the provider, which cancels the `StreamSubscription`, aborting the Dio cancel token and closing the HTTP stream immediately.
  - **App lifecycle (`AppLifecycleListener` / `WidgetsBindingObserver`):** When the app transitions to background (`paused` / `hidden` / `detached`), `AiJobStatusController` cancels the active SSE subscription immediately so zero network wakeups occur in the background. When the app returns to `resumed` while `AiJobStatusScreen` is mounted, the controller executes **one** snapshot `GET /v1/ai-import/jobs/{id}` (`getJobAndCache`) and, if the job is still non-terminal, opens a fresh SSE subscription.
- **Reconnect within a foreground session & client-side keep-alive watchdog:**
  - Because SSE is strictly unidirectional (no client-to-server `Ping`), a silent state drop in a middlebox (Citrix NetScaler, corporate firewall, or carrier NAT) leaves a half-open socket unless the client enforces a read-idle deadline. The SSE `Dio` request therefore sets `receiveTimeout: const Duration(seconds: 65)` (> 2× the server's 30 s `: keep-alive` cadence): if 65 s pass without any data or `: keep-alive` frame, Dio aborts the hung stream with `receiveTimeout`.
  - If the SSE stream drops transiently or hits a middlebox transaction timeout/read-idle timeout while the screen remains foregrounded, `AiImportRepository.watch(jobId)` retries using the existing bounded `ReconciliationScheduler`, passing the last received SSE `id` in the `Last-Event-ID` header. On reconnect, the server sends a fresh full snapshot as the first event.
- **Jobs overview list (`AiImportJobsScreen`, issue #547) stays watch-free:**
  - `AiImportJobsViewController` continues to issue **one** `GET /v1/ai-import/jobs` on open and on manual pull-to-refresh, opening **zero** SSE connections (preserving the #547 D5 unit-test invariant that `watch` call count is zero on the list screen).
  - Because `GET /v1/ai-import/jobs` returns `AiImportJob` rows that now include `progress`, each running row on `AiImportJobsScreen` renders the stage/chunk/episodes summary as of the latest fetch.

### D6 — Pinned-CA TLS Streaming over `Dio` (`ResponseType.stream`, ADR-024 / ADR-032)

**Decision:**
- Extend the transport-layer streaming interceptor in `frontend-flutter/lib/src/network/` (alongside `PdfStreamingInterceptor`) or pass `Options(responseType: ResponseType.stream, headers: {'Accept': 'text/event-stream', if (lastEventId != null) 'Last-Event-ID': lastEventId})` on the `api.dio.get<ResponseBody>('/v1/ai-import/jobs/$jobId/events', cancelToken: cancelToken, ...)` call inside `AiImportRepository.watch`.
- Because `api.dio` is built by `buildPinnedDio` (`frontend-flutter/lib/src/network/api_client.dart`), the SSE stream automatically uses the fail-closed `SecurityContext(withTrustedRoots: false)` pinned CA (ADR-024 / ADR-032), `AuthTokenInterceptor` (`Authorization: Bearer ...` over HTTPS), and `ActiveBlockInterceptor`. No third-party SSE package that creates its own unpinned `HttpClient` is permitted.
- A small pure Dart SSE line parser (`SseEventParser` in `lib/core/` or `lib/data/`) transforms the `Stream<Uint8List>` chunks (`utf8.decoder` → `LineSplitter`) into `(id, event, data)` frames, ignores `: keep-alive` comment lines, and decodes `event: job` JSON payloads via the generated `BreakdownApi` serializers into `AiImportJobResponse`.

### D7 — Explicit Disposition of HTTP/3 and Rejected Alternatives

**Decision:**
1. **HTTP/3 (QUIC) is an explicit non-goal:**
   - **Backend (`axum`):** `axum 0.8` / `hyper 1.x` is TCP-only (HTTP/1.1 and HTTP/2). Supporting HTTP/3 in Rust requires non-first-party bridges (`h3-axum` / `h3-quinn`) and UDP port/firewall provisioning at the reverse proxy.
   - **Client (`Flutter` / `Dio`):** `dart:io`'s `HttpClient` and `dio`'s `IOHttpClientAdapter` support HTTP/1.1 and HTTP/2 over TLS, not QUIC. Adopting HTTP/3 in Flutter requires either native platform bridges (`native_dio_adapter` → Android Cronet / Apple `URLSession`) or a Rust FFI HTTP stack (`rhttp`), both of which bypass `dart:io`'s `SecurityContext(withTrustedRoots: false)` and would require re-implementing and auditing ADR-024/ADR-032 CA pinning per platform.
   - **Value assessment:** For a single foreground SSE stream, HTTP/1.1 or HTTP/2 over TLS provides identical push latency and keep-alive semantics without risking TLS pinning regressions. HTTP/3 may be revisited only if `dart:io` gains native QUIC support with `SecurityContext` parity.
2. **Webhooks — rejected:** Mobile clients are behind carrier NAT and OS Doze; webhooks require public reachability, device-authenticated callback endpoints, and wake locks that harm battery.
3. **Periodic polling — rejected:** High battery cost and artificial latency; replaced by SSE while foregrounded + single snapshot GET on resume/manual refresh.
4. **WebSockets / GraphQL subscriptions — rejected:** Job progress is strictly server-to-client unidirectional; SSE works over standard HTTP with built-in `Last-Event-ID` semantics and no protocol-upgrade or firewall issues.
5. **FCM / APNs push notifications — out of scope:** Could be an optional future enhancement for "import finished while app closed", but is not an in-app live progress channel and introduces external cloud dependencies not needed here.

## Handoff-Prompt / Task-Spec Architecture Review Checklist (`AGENTS.md` §3)

- [x] **Write-side queries a read-model projection?** No. Workers only write operational progress to `ai_import.ai_import_job`; the SSE handler is a read endpoint at the API edge.
- [x] **`unwrap`/`expect`/`panic` in hot paths (adapters, sagas, projectors, handlers)?** No. All SQL, JSON, and stream operations use `?` / explicit error matching and log-and-recover on the background `PgListener`.
- [x] **Test-only helpers called from production spawn paths?** No.
- [x] **Audit metadata (`project_id`) coupled to projector presence?** No. Operational queue only; emits no domain events.
- [x] **Fallible result discarded with `let _ = <call>`?** No. Broadcast sends with zero active receivers are handled via explicit match or helper, and Flutter `StreamSubscription.cancel()` uses `unawaited(...)` per `breakdown_lints`.
- [x] **Test-only helper (`*_for_test`) without `#[cfg(feature = "test-support")]` gating?** No.
- [x] **New cross-aggregate invariant without API-edge pre-check (409), authoritative backstop, and projector-failure spec?** No new cross-aggregate invariant.

## Risks / Trade-offs

- **[Reverse-proxy / enterprise ADC buffering or silent drops (e.g. Citrix NetScaler)]** → Mitigation: Handler sets `Cache-Control: no-store, no-transform` (RFC 9111 §5.2.2.4 — prevents ADC gzip/transform buffering) and `X-Accel-Buffering: no`, and sends `: keep-alive` comments every 30 s; client sets a 65 s `receiveTimeout` watchdog to detect silent half-open drops and relies on snapshot-first reconnects when an ADC enforces a hard transaction duration limit.
- **[Broadcast receiver lag on bursty updates]** → Mitigation: `AiJobEventHub` maps `RecvError::Lagged(_)` to a wake-up signal; because the SSE handler always reads the latest state from `AiImportQueue::get(id)` rather than trusting the notification payload alone, lagging receivers never lose the latest progress or terminal state.
- **[Displaced worker writes stale progress after lease expiry]** → Mitigation: `mark_progress` uses the exact same `WHERE id = $1 AND status = 'running' AND claimed_by = $2` owner fence as `mark_running`/`mark_succeeded` and returns `DomainError::Conflict` on 0 rows affected.
- **[Drift cache schema change for `progress`]** → Mitigation: Add a nullable `progressJson` text column to `AiImportJobsCache` with a clean Drift schema version bump and migration step (`frontend-flutter/AGENTS.md` §8).

## Migration Plan

1. **Database migration (`20261012000001_ai_import_job_progress.{up,down}.sql`):**
   - `UP`: `ALTER TABLE ai_import.ai_import_job ADD COLUMN progress JSONB;`
   - `DOWN`: `ALTER TABLE ai_import.ai_import_job DROP COLUMN progress;`
   - Backward-compatible: existing rows have `progress = NULL`, which deserializes to `progress: None`.
2. **Wire compatibility:**
   - `progress` on `AiImportJob` is optional/nullable (`#[serde(default)]`), and `GET /v1/ai-import/jobs/{id}/events` is a new additive route under `/v1` (ADR-021 MINOR / additive).
   - `GET /v1/ai-import/jobs/{id}` remains unchanged for snapshot reads on resume and legacy callers.

## Open Questions

None — both architectural decisions (D4: Postgres `NOTIFY` + single `PgListener` → `broadcast` hub with hexagonal port for future SQLite mode; D5: SSE on `AiJobStatusScreen` only, `AiImportJobsScreen` stays one-shot GET + progress display) were confirmed with the user during exploration.
