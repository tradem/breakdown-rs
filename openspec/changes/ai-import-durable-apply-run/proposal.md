<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3 (neuralwatt) -->

## Why

A live test of the AI import surfaced a defect that no preview-side fix can
reach: **applying a preview is bound to the HTTP request that started it**. The
handler awaits the whole row loop
(`crates/api/src/handlers/mod.rs` → `ApplyWorker::apply_script`), so

- an Android suspend (Doze), a Wi-Fi→cellular handover or any dropped socket
  **drops the handler future** and the apply stops mid-row — what the user sees
  is an interrupted import and (correctly) an `ApplyRunGuard` that clears the
  run's progress, so the remaining-time display freezes and the only remedy is a
  new `POST /apply`;
- the apply's own progress stream (`GET /jobs/{id}/apply-events`, issue #762)
  dies with the request, although it is exactly the surface that should outlive
  it;
- the client cannot distinguish "the POST died" from "the apply failed":
  `isAmbiguousTimeout` covers only the three Dio timeout codes, so a
  `connectionError` (the suspend case) is a *definitive* failure and the user is
  told the apply failed while the server may have committed half of it.

The preview already models durability correctly (queue row, owner-fenced claim,
lease heartbeat, restart recovery). The apply does not. This change gives the
apply the same lifecycle: a **durable run** that a dropped client can re-attach
to instead of restarting.

Duration is addressed separately and additively by the performance PR
(`CachedMappings` per-run mapping cache, single per-run season read, per-phase
apply timing); this proposal does not depend on it.

## What Changes

- **BREAKING (API):** `POST /v1/ai-import/jobs/{id}/apply` no longer performs
  the apply inline. It validates the request, claims the run and **dispatches**
  it, answering `202 Accepted` with an `ApplyRunAccepted` descriptor
  (`run_id`, `stage`, `started_at`). The apply's counters move to the run's
  terminal frame on `GET /v1/ai-import/jobs/{id}/apply-events`.
- The run is executed by a server-side task holding an owner-fenced lease on the
  job's apply slot, so **a client disconnect cannot cancel it**: the connection
  ends, the run continues, and the client re-attaches.
- The run's outcome (`ApplyAiImportResponse`: counters, `unapplied_outfits`,
  `applied_episodes`, `skipped_day_groups`) is persisted on the run slot and
  delivered both on the apply stream's terminal frame and on
  `GET /v1/ai-import/jobs/{id}`.
- A second `POST /apply` while a live run owns the slot keeps answering
  `409 ai-import.apply-in-flight` (issue #805) — now with the documented client
  reaction **attach, don't error**. The existing staleness window
  (`ApplyProgress::STALE_AFTER`) remains the crash-recovery path: a run whose
  owner went silent is stealable.
- Flutter: a dropped or timed-out apply POST becomes a **resumable** state
  (`connectionError` joins the ambiguous class); the apply screen re-attaches to
  a live run on resume instead of demanding a restart, and the "take over a
  stale run" affordance is offered only after the server's own window elapsed.

## Capabilities

### New Capabilities

- (none — the change reshapes an existing capability rather than adding one)

### Modified Capabilities

- `ai-import`: the apply's lifecycle changes from request-scoped work to a
  durable run (dispatch/attach/steal), and the apply response contract moves
  from the `POST` body to the run's terminal state. Adds requirements, does not
  remove the idempotent upsert protocol.
- `flutter-ai-import-workflow`: an interrupted apply is **resumed**, not
  restarted; the client attaches to a live run and treats a dropped POST as
  ambiguous until the server's window says otherwise.

## Impact

- **Affected code:** `crates/api/src/handlers/mod.rs` (`apply_ai_import`,
  `get_ai_import_apply_events`), `crates/infra/src/ai/queue.rs`
  (claim/dispatch/complete of the apply slot), `crates/infra/src/ai/workers.rs`
  (`ApplyWorker::apply_script` entry point and the run guard),
  `crates/core/src/ai/ports.rs` + `views.rs` (run descriptor, persisted result),
  `crates/api/src/main.rs` (worker wiring / shutdown join),
  `backend/openapi.yaml`, `frontend-flutter/vendor/breakdown_api/**` (regenerated
  client), `frontend-flutter/lib/data/ai_import_repository.dart`,
  `frontend-flutter/lib/features/ai_import/import_jobs/apply_*`.
- **APIs:** `POST /v1/ai-import/jobs/{id}/apply` → `202`; `GET
  /v1/ai-import/jobs/{id}/apply-events` gains the terminal result frame;
  `GET /v1/ai-import/jobs/{id}` gains the run's persisted result.
- **Dependencies:** none new (reuses the existing queue port, SSE hub and
  reservation/mapping idempotency).
- **Operational:** a run now outlives its request, so the API's graceful
  shutdown must join the dispatched apply tasks (the same ordering rule the
  concurrency permits already require).
- **Docs/CHANGELOG:** `backend/CHANGELOG.md` (202 + run contract), `docs/errors/`
  if a new code is needed for "run already finished" reads, `backend/AGENTS.md`
  §1 cross-aggregate doctrine untouched.
