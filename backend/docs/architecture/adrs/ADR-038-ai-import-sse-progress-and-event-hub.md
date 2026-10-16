<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: gemini-4-argon (google) -->

# ADR-038: AI Import Push-Based Job Progress — SSE Snapshot+Deltas, Hexagonal Event Hub (Postgres `NOTIFY` + SQLite Seam), and Client Battery Contract

**Status**: Proposed
**Date**: 2026-10-16
**Author**: Tobias Rademacher (@tradem); gemini-4-argon (google)
**Related**: ADR-005 (Axum), ADR-006 (utoipa OpenAPI), ADR-024 (In-Transit TLS), ADR-030 (AI Import Bounded Context), ADR-031 (HTTP Error Surface), ADR-032 (Flutter Client TLS Pinning)
**Source change**: tracked in GitHub issue #664 (`openspec/changes/issue-664-ai-import-sse-progress/`)

---

## Context

Per ADR-030, AI script and schedule imports run asynchronously as operational
jobs (`ai_import.ai_import_job`) rather than event-sourced aggregates. Until
now, `AiImportJob` exposed only a coarse lifecycle status (`pending`,
`running`, `succeeded`, `failed`, `dead_letter`, `payload_unavailable`) and
retry/attempt failure metadata (issues #637, #639).

Two concrete problems motivated issue #664:

1. **No extraction-stage or episode visibility:** A multi-chunk screenplay
   import (up to 128 scene chunks × 120 s timeout) gives the user no signal
   about *where* processing is (text extraction, chunk `k` of `N`, schedule
   merge, or preview write) or *which* episodes (`Ep.: 3 (Titel)`) have been
   discovered in the document so far — even though the deterministic scanner
   in `crates/core/src/ai/preview.rs` (issue #581) already extracts episode
   markers before the first LLM call.
2. **Client polling is battery-hostile and bounded-fragile:** In the Flutter
   client, `AiImportRepository.watch(jobId)` polled `GET /v1/ai-import/jobs/{id}`
   up to 30 times via `ExponentialBackoffScheduler`. Periodic polling wakes the
   mobile radio repeatedly, adds artificial backoff latency, and exhausts on
   legitimately long multi-episode screenplay imports.

Key architectural constraints shaping the solution:

- **CQRS & operational queue boundary (`AGENTS.md` §1, ADR-030):** `AiImportJob`
  is an operational queue record, not domain business truth. Workers must never
  query domain read projections, and all worker status/progress writes must be
  **owner-fenced** (`WHERE id = $1 AND status = 'running' AND claimed_by = $2`,
  issue #177) so a worker whose lease expired cannot overwrite a reclaiming
  worker's state.
- **Handler-internal `AUTHZ-GATE` (`AGENTS.md` §3):** Any job-scoped endpoint
  under `/v1/ai-import/jobs/*` sits behind `Requirement::Authenticated` and
  must run `authorize_ai_job(&state, &current_user, &job, Action::Read)` inside
  the handler before emitting any job data.
- **Pinned-CA TLS on the Flutter client (ADR-024, ADR-032):** The client trusts
  only the bundled per-flavor root CA (`SecurityContext(withTrustedRoots: false)`).
  Any streaming transport must reuse the existing pinned `Dio` pipeline
  (`buildPinnedDio`).
- **Database portability across PostgreSQL and a future SQLite operating mode:**
  While the current production runtime uses PostgreSQL (`PgAiImportQueue`), the
  project plans to support an additional single-node/embedded operating mode
  with **SQLite** as the read-model and operational database. Neither `crates/core`
  nor `crates/api` may couple to PostgreSQL-specific `LISTEN/NOTIFY` primitives.

## Decision

We adopt **Server-Sent Events (SSE)** at `GET /v1/ai-import/jobs/{id}/events`
with a **snapshot-first + deltas** protocol, backed by an owner-fenced
`progress` JSONB column on `ai_import_job` and a **hexagonal `AiJobEventHub`**
that bridges PostgreSQL `NOTIFY` (`PgListener`) in multi-instance Postgres mode
while working purely in-process for future SQLite and test modes.

### 1. SSE Endpoint (`GET /v1/ai-import/jobs/{id}/events`)

- **Authorization before stream open:** The handler checks `ai_import_enabled`
  (`404 ai-import.disabled`), loads the job (`404 ai-import.not-found`), and
  runs `// AUTHZ-GATE: authorize_ai_job(&state, &current_user, &job, Action::Read)`
  (`403 ai-import.forbidden` as RFC 9457 `application/problem+json`, ADR-031)
  *before* returning the `200 OK` `text/event-stream` response.
- **Snapshot-first + self-contained `event: job` frames:** On every initial
  connect and every `Last-Event-ID` reconnect, the handler subscribes to the
  queue's event stream first (preventing race gaps) and immediately emits the
  current `AiImportJobResponse` as the first `event: job` frame with a
  monotonic `id` watermark (`updated_at` in unix microseconds). Subsequent
  transitions also emit the full compact `AiImportJobResponse` (~500–800 bytes),
  so a reconnecting client needs no catch-up polling or server-side event
  ring buffer.
- **Keep-alive and terminal close:** The stream emits `: keep-alive` comment
  frames every 30 s (`Cache-Control: no-store, no-transform`,
  `X-Accel-Buffering: no`) and
  closes automatically right after emitting a frame whose `job.status.is_terminal()`
  is `true` (`succeeded`, `dead_letter`, `payload_unavailable`). Retryable
  `failed` jobs are non-terminal and keep the stream open across retry backoff
  windows while the client remains foregrounded.

### 2. Owner-Fenced, Throttled `mark_progress` and Zero-Token `episodes_seen`

- `AiImportJob` gains `#[serde(default)] pub progress: Option<AiImportProgress>`,
  stored in `ai_import.ai_import_job.progress JSONB` (migration
  `20261012000001_ai_import_job_progress`):
  - `stage: AiImportStage` (`extracting_text`, `extracting`, `merging`,
    `storing_preview`)
  - `chunk: Option<u32>` (1-based completed/active chunk index)
  - `chunks_total: Option<u32>` (total scene chunks in the document)
  - `episodes_seen: Vec<String>` (deduplicated labels in first-seen order, e.g.
    `["Ep. 3", "Ep. 4"]`, derived from deterministic `Ep.:` markers and
    extracted `DraftEpisode` metadata at zero extra LLM token cost).
- `AiImportQueue::mark_progress` is **owner-fenced** (`WHERE id = $1 AND status =
  'running' AND claimed_by = $2`; zero rows affected → `DomainError::Conflict`)
  and **throttled** to stage boundaries and once per completed chunk (never per
  LLM token). Re-claiming a job after a retryable failure resets `progress` to
  `NULL`.

### 3. Hexagonal Event Distribution (`AiJobEventHub` + Postgres Bridge + SQLite Seam)

- **Port contract (`crates/core`):** `AiImportQueue::subscribe(&self, id: AiImportJobId)`
  returns a storage-agnostic `Pin<Box<dyn Stream<Item = AiImportJobId> + Send>>`.
  Neither `core` nor `api` knows about PostgreSQL `LISTEN/NOTIFY`.
- **In-process hub (`crates/infra`):** `AiJobEventHub` wraps a bounded
  `tokio::sync::broadcast::Sender<AiImportJobId>`. Every queue mutation that
  changes job status or progress notifies the hub on commit. If a subscriber
  lags (`RecvError::Lagged`), the stream yields a synthetic wake-up so the SSE
  handler re-reads the authoritative row via `queue.get(id)`.
- **PostgreSQL operating mode (`PgAiImportQueue`):**
  - Fenced SQL `UPDATE` statements invoke `pg_notify('ai_import_job_events', id::text)`
    inside the same SQL statement, guaranteeing that rolled-back or zero-row
    fenced writes never emit notifications and keeping the payload to 36 bytes
    (well below PostgreSQL's 8000-byte `NOTIFY` limit).
  - A single background `PgListener` task per API process (`spawn_pg_job_event_listener`)
    listens on `'ai_import_job_events'` and forwards job IDs into the local
    `AiJobEventHub`. This uses **one** connection per API node regardless of how
    many SSE clients are connected.
- **Future SQLite operating mode (`SqliteAiImportQueue`):**
  - Because SQLite operates in-process without cross-process `LISTEN/NOTIFY`,
    a future `SqliteAiImportQueue` adapter simply holds the same `AiJobEventHub`
    and calls `hub.notify(id)` after its SQLite transaction commits. No changes
    to `core`, `api`, or the SSE handler are required.

### 4. Flutter Battery Contract & Pinned-CA Streaming

- **Single foreground SSE consumer (`AiJobStatusScreen` only):**
  - `AiJobStatusScreen` (via `AiJobStatusController`) subscribes to
    `GET /v1/ai-import/jobs/{id}/events` while mounted and foregrounded.
  - Leaving the screen or backgrounding the app (`paused` / `hidden` /
    `detached`) immediately cancels the stream subscription (`CancelToken`),
    producing zero background network wakeups.
  - On app resume (`resumed`) while `AiJobStatusScreen` is mounted, the
    controller performs **one** snapshot `GET /v1/ai-import/jobs/{id}` and
    re-opens the SSE stream only if the job is still non-terminal.
  - `AiImportJobsScreen` (the #547 overview list) opens **zero** SSE streams:
    it keeps its one-shot `GET /v1/ai-import/jobs` fetch and manual
    pull-to-refresh, rendering each row's `progress` summary from the fetched
    DTOs.
- **Pinned-CA TLS preservation (ADR-024, ADR-032):** The SSE stream is consumed
  via `api.dio` (`ResponseType.stream`), reusing `buildPinnedDio`'s
  `SecurityContext(withTrustedRoots: false)`, `AuthTokenInterceptor`, and
  `ActiveBlockInterceptor`.

### 5. Explicit Non-Goal: HTTP/3 (QUIC)

HTTP/3 is explicitly evaluated and rejected as a non-goal for this change:

- On the backend, `axum 0.8` / `hyper 1.x` is TCP-only (HTTP/1.1 and HTTP/2);
  HTTP/3 requires third-party QUIC bridges (`h3-axum` / `h3-quinn`).
- On the Flutter client, `dart:io` `HttpClient` and `dio`'s `IOHttpClientAdapter`
  do not speak QUIC. Adopting HTTP/3 requires native platform adapters
  (`native_dio_adapter` → Cronet / `URLSession`) or Rust FFI (`rhttp`), both of
  which bypass `dart:io`'s `SecurityContext(withTrustedRoots: false)` and would
  compromise or duplicate ADR-024/ADR-032 CA pinning.
- A single foreground SSE stream gains nothing material from QUIC multiplexing
  over HTTP/1.1 or HTTP/2 TLS.

## Consequences

### Positive

- **Immediate user feedback & zero-cost episode preview:** Users see the active
  extraction stage, `chunk / chunks_total` progress, and discovered episodes
  (`Ep. 3`, `Ep. 4`) as chunks complete, with zero additional LLM tokens.
- **Battery-friendly:** Eliminates periodic polling wakeups; backgrounding the
  app closes the stream immediately, and resuming runs a single snapshot GET.
- **Connection-pool safe & multi-DB portable:** At most one `PgListener`
  connection per API instance in PostgreSQL mode, and a zero-friction in-process
  `AiJobEventHub` seam for the planned SQLite operating mode.
- **TLS pinning intact:** Streaming through the existing `Dio` adapter preserves
  ADR-024 / ADR-032 fail-closed root CA pinning without introducing a second
  HTTP stack.

### Negative

- **Long-lived HTTP connections while `AiJobStatusScreen` is open:** Each
  foreground watcher holds one open HTTP response stream until the job reaches a
  terminal state or the user navigates away. Mitigated by restricting SSE to the
  single-job status screen (never the jobs list) and closing on terminal status
  or backgrounding.
- **Reverse-proxy & enterprise ADC middlebox sensitivity (e.g. Citrix NetScaler):**
  Unlike discrete polling requests (which finish immediately) or WebSockets
  (which switch via `101 Switching Protocols` into an uninspected L4 tunnel),
  SSE is a long-lived chunked HTTP `200 OK` response. Enterprise ADCs/WAFs
  (such as Citrix NetScaler, F5 BIG-IP, or corporate DLP proxies) can interfere
  with SSE in four specific ways (see *Operational Limits of SSE vs. Rejected
  Alternatives* below): response-body buffering/compression, hard transaction
  duration caps, silent half-open connection drops, and HTTP/1.1 backend
  connection-pool pinning. Mitigated via `Cache-Control: no-store, no-transform`,
  `X-Accel-Buffering: no`, 30 s `: keep-alive` frames paired with a 65 s
  client-side `receiveTimeout` watchdog, and snapshot-first reconnects.

## Operational Limits of SSE vs. Rejected Alternatives (NetScaler / ADC Analysis)

Where SSE has structural limits that Polling or WebSockets do not, and how this
architecture bounds them:

| Limit / Failure Mode | Why SSE is affected | How Polling / WebSockets differ | Our Mitigation in Breakdown RS |
|---|---|---|---|
| **1. Middlebox response buffering & GZIP coalescing** (Citrix NetScaler HTTP Compression / Integrated Caching / AppFirewall WAF) | An ADC sees a standard `200 OK` (`Transfer-Encoding: chunked`) and may buffer 4–64 KB before flushing to compress or scan the body, delaying ~500 B SSE frames until job completion. | **Polling:** `Content-Length` is known and EOF is immediate. **WebSocket:** `101 Switching Protocols` bypasses HTTP body compression/WAF body buffering once upgraded. | Emit `Cache-Control: no-store, no-transform` (RFC 9111 §5.2.2.4 — forbids proxy compression/transformation) and `X-Accel-Buffering: no`; disable compression on `/v1/ai-import/jobs/*/events` at the edge (Caddy, ADR-025). |
| **2. Hard HTTP transaction timeout** (WAF / ADC max request duration) | Some NetScaler / WAF profiles enforce a maximum *total* duration per HTTP request (e.g. 120–300 s) even when bytes flow, resetting the stream mid-import. | **Polling:** each request takes < 50 ms. **WebSocket:** governed by separate long-lived tunnel timeouts. | **Snapshot-first on every reconnect:** when an ADC resets the stream after N minutes, the client reconnects with `Last-Event-ID` and immediately receives the latest full `AiImportJobResponse` snapshot as frame 1 — zero lost progress. |
| **3. Silent half-open TCP drops** (Carrier NAT / stateful firewall drop without `FIN`/`RST`) | SSE is strictly unidirectional (server → client). A client waiting on `socket.read()` has no application-level ping to send and will hang indefinitely if a NAT/ADC silently drops state. | **Polling:** next request fails fast on connect/send. **WebSocket:** bidirectional `Ping`/`Pong` frames (RFC 6455 §5.5.2) detect dead peers from either side. | **Client-side read-idle watchdog (`receiveTimeout: 65s`):** since the server sends `: keep-alive` every 30 s, > 65 s of silence proves a dead path; Dio aborts the stream and triggers bounded reconnect + snapshot recovery. |
| **4. HTTP/1.1 connection pinning & browser 6-stream limit** | Over HTTP/1.1, each SSE stream pins one TCP socket for its lifetime (browsers cap HTTP/1.1 at 6 connections per origin; NetScaler HTTP/1.1 backend multiplexing can un-multiplex or pin backend sockets). | **Polling:** releases the socket immediately. **WebSocket:** typically multiplexes all app topics over a single shared socket. | In Flutter, **at most 1 SSE stream** is ever open (`AiJobStatusScreen` only; `AiImportJobsScreen` opens 0 streams, Decision 4). Over HTTP/2 (Caddy edge default, ADR-025), SSE multiplexes as a single H2 stream. If `frontend-web/` later needs multi-resource live streams, evaluate H2 enforcement or a shared multiplexer then. |

## Alternatives Considered

1. **Client-side periodic polling (`ExponentialBackoffScheduler`):**
   Currently implemented, but causes unnecessary radio wakeups, high latency
   between backoff ticks, and watch exhaustion on long scripts. Retained only as
   one-shot manual refresh (`pull-to-refresh`) and single snapshot GET on app
   resume.
2. **Webhooks:**
   Server-to-server push cannot reach mobile devices behind NAT/Doze without
   public relay infrastructure and wake locks that drain battery.
3. **WebSockets or GraphQL Subscriptions:**
   Introduce bidirectional framing or a second query protocol for a strictly
   unidirectional server-to-client progress feed where standard HTTP SSE +
   `Last-Event-ID` suffices.
4. **Dedicated `PgListener` per SSE client connection:**
   Would allocate one PostgreSQL connection per watching client, risking pool
   exhaustion under concurrent imports and coupling the API layer directly to
   PostgreSQL.
5. **FCM / APNs push notifications:**
   Useful only as a future optional notification when an import finishes while
   the app is closed; unsuitable for live in-app chunk progress and requires
   external cloud push credentials.

## Notes

- The worker's `claim_next_kind_reconciling … FOR UPDATE SKIP LOCKED` loop
  remains unchanged as the crash-safe job claiming mechanism ("job queues are a
  Postgres strength, not an ES deficiency", `AGENTS.md` §1). `LISTEN/NOTIFY`
  is used here strictly for status/progress fan-out to SSE subscribers.
