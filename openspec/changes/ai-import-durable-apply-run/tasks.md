<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3 (neuralwatt) -->

## 1. Run slot on the job row (core + infra)

- [ ] 1.1 Add `ApplyState` (`idle`/`requested`/`running`/`done`/`failed`) to
      `crates/core/src/ai/views.rs` with `Serialize`/`ToSchema`, and expose
      `apply_state` + `apply_result: Option<ApplyAiImportSummary>` on
      `AiImportJob`/`AiImportJobResponse` (additive wire fields, defaults for
      pre-change rows).
- [ ] 1.2 Migration: `ai_import.ai_import_job.apply_state` (enum-as-text, default
      `idle`), `apply_request JSONB`, `apply_result JSONB`, plus an index that
      lets the worker select `apply_state = 'requested'`.
- [ ] 1.3 Extend `AiImportQueue` (port + `PgAiImportQueue` + `FakeAiImportQueue`)
      with owner-fenced `request_apply_run`, `mark_apply_running`,
      `complete_apply_run`, `fail_apply_run`; every transition writes
      `apply_state` and the progress payload in one statement pair, and returns
      `Conflict` when the caller no longer owns the claim.
- [ ] 1.4 Integration test (`crates/integration-tests`): the four transitions are
      owner-fenced, `complete_apply_run` persists the result and clears the
      progress payload, and a displaced owner gets `Conflict` without touching
      the new owner's row.

## 2. Dispatch from the handler (api)

- [ ] 2.1 Split `apply_ai_import` at the first write: keep validation as is, then
      claim + persist the resolved `ApplyScriptRequest`/`ScheduleApplyRequest` as
      `apply_request`, flip `requested`, and answer `202 ApplyRunAccepted
      { run_id, stage, started_at }`.
- [ ] 2.2 Keep the `409 ai-import.apply-in-flight` refusal (age + window) exactly
      as shipped in #805, now emitted by the claim alone — no run is executed
      before the answer.
- [ ] 2.3 Update `backend/openapi.yaml` (`UPDATE_OPENAPI=1 cargo test -p api
      --test contract openapi_drift`) and regenerate the Dart client under
      `frontend-flutter/vendor/breakdown_api/`.
- [ ] 2.4 Handler tests: `202` shape, no counters in the body, validation
      failures unchanged (same codes), and a live-run refusal.

## 3. Worker-owned run (infra)

- [ ] 3.1 Move the apply entry point from the request path to the worker:
      `ApplyWorker::apply_script` (and the schedule twin) take the persisted
      `apply_request`; `apply_state = running` is written before the first row.
- [ ] 3.2 Move `ApplyRunGuard` from the request future to the run task and clear
      the progress payload only in `complete_apply_run` / `fail_apply_run`
      (a dropped connection must no longer clear it).
- [ ] 3.3 Persist `ApplyAiImportResponse` on success and the registered problem
      `code` on failure, then set `done`/`failed`.
- [ ] 3.4 Teach the AI worker loop to claim `apply_state = 'requested'` rows (same
      claim/lease machinery as `pending` jobs) and to recover a `running` row
      whose owner went silent (`ApplyProgress::STALE_AFTER`).
- [ ] 3.5 Shutdown: cancel and join dispatched apply tasks before the
      pool/limiter teardown, following the documented permit ordering; assert it
      with the existing shutdown/fault-injection harness.
- [ ] 3.6 Unit tests: a dispatched run survives a dropped handler future; a
      re-driven run converges (no duplicate aggregates) against the existing
      `FakeMappings`/`FakeSceneCommands` doubles.

## 4. Serving the outcome (api)

- [ ] 4.1 `GET /jobs/{id}/apply-events`: emit the persisted result as the terminal
      frame and close; a late attach for a finished run gets that frame
      immediately (no idle window).
- [ ] 4.2 `GET /jobs/{id}`: carry `apply_state` + `apply_result`.
- [ ] 4.3 SSE handler tests: terminal frame after `done`, immediate terminal frame
      on a late attach, `failed` run reports its code.

## 5. Flutter re-entry (frontend)

- [ ] 5.1 `AiImportRepository.apply`: handle `202` (open the stream, render the
      terminal frame's result) and drop the counters-from-POST path.
- [ ] 5.2 Rename `isAmbiguousTimeout` → `isResumableDispatch` and add
      `transport.connectionError` (+ the streamed-body `unknown` case); a dropped
      dispatch re-reads the job and attaches instead of surfacing an error.
- [ ] 5.3 Apply controller/screen: decide from `apply_state` on entry — offer
      Apply / attach to the live run / render the persisted result. Keep the
      takeover gated on the server-reported window (no client constant).
- [ ] 5.4 Widget/controller tests: suspend-and-resume attaches without a second
      dispatch; `connectionError` renders progress, not the error narrative;
      finished-run entry renders the persisted counters.

## 6. Documentation and release

- [ ] 6.1 `backend/CHANGELOG.md`: **BREAKING** `POST /apply` → `202` +
      `ApplyRunAccepted`, the terminal-frame result, and the attach-on-`409`
      semantics.
- [ ] 6.2 `backend/.github/instructions/ai-import.instructions.md`: the run
      lifecycle (dispatch, attach, steal, shutdown join) next to the existing
      claim/lease rules.
- [ ] 6.3 `openspec` archive after implementation; confirm the live test (apply
      of 50-60 scenes with a mid-run suspend) resumes instead of restarting.
