<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

# 800 — Tasks

## 1. Core (wire + port)

- [x] 1.1 `ApplyRunId` newtype in `crates/core/src/ai/views.rs` (transparent
      `Uuid`, `ToSchema`), re-exported from `core::ai`.
- [x] 1.2 `ApplyProgress.run_id: ApplyRunId` (additive `serde(default)`; a
      pre-#800 payload decodes to the nil id, which never owns a claim).
- [x] 1.3 `AiImportJob.applied: bool` (additive `serde(default)`), derived by
      the adapter from the existing `accept_as_is IS NOT NULL`.
- [x] 1.4 `ApplyRunState { owner: Option<ApplyRunId>, seq: i64, progress }` +
      port methods `claim_apply_run(id, run_id) -> bool` and
      `apply_run_state(id) -> Option<ApplyRunState>`; `mark_apply_progress`
      takes the run identity. Defaults keep every fake compiling.
- [x] 1.5 Register `ai-import.apply-in-flight` (`409`, no extensions) and bump
      `PROBLEM_CODE_COUNT`; Fluent copy (de/en).

## 2. Migration

- [x] 2.1 `20261104000001_ai_apply_run_identity` — `apply_run_id UUID` +
      `apply_run_seq BIGINT NOT NULL DEFAULT 0` (+ down, + column comments).

## 3. Infra

- [x] 3.1 `claim_apply_run`: conditional `UPDATE … WHERE id = $1 AND
      status = 'succeeded' AND (apply_run_id IS NULL OR payload stale)`,
      `apply_run_seq = apply_run_seq + 1`, `pg_notify`.
- [x] 3.2 `mark_apply_progress`: ownership-conditioned write; `None` clears the
      payload **and** `apply_run_id`, never `apply_run_seq`.
- [x] 3.3 `apply_run_state` read (owner + seq + decoded payload).
- [x] 3.4 `ApplyWorker::apply_script`: generate the run id, claim, hold the
      `Drop` guard, disarm after the worker's own clear.
- [x] 3.5 Heartbeat: refresh `updated_at` while a row is in flight, at
      `STALE_AFTER / 4`, run-scoped and aborted with the run.
- [x] 3.6 Test fake (§5 sites: port default, `PgAiImportQueue`, infra fake, api
      fake, integration adapter).

## 4. API

- [x] 4.1 `classify_apply_run(progress, seq, baseline_seq, saw_run, now)`.
- [x] 4.2 `sse_apply_stream` re-reads `apply_run_state` and takes the
      subscribe-time seq as its baseline.
- [x] 4.3 `openapi.yaml` regenerated (`UPDATE_OPENAPI=1 cargo test -p api
      --test contract openapi_drift`).

## 5. Client (`frontend-flutter`)

- [x] 5.1 `bash frontend-flutter/scripts/regen-client.sh`.
- [x] 5.2 Apply-run boundary: `progress.startedAt` → `progress.runId`
      (`apply_screen.dart`, ETA ownership).
- [x] 5.3 `ai-import.apply-in-flight` = wait, not block
      (`applyWithReconciliation` + localized copy).
- [x] 5.4 "Bereits importiert" badge in the jobs list from `job.applied`.
- [x] 5.5 Re-apply behind an explicit confirmation (recovery preserved).
- [x] 5.6 ARB de/en + `flutter gen-l10n`; tests (unit/widget/golden).

## 6. Wrap-up

- [x] 6.1 Four CHANGELOGs; versions `core 0.56.0`, `infra 0.65.0`,
      `api 0.55.0`.
