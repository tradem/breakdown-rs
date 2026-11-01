<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

# 762 — Tasks

## 1. Core: the progress view carries a time anchor and a byte budget (PR 1)

- [x] 1.1 `core/ai/views.rs`: `AiImportProgress.started_at` (optional, the
      claim stamp of the current attempt) — additive with `serde(default)`.
- [x] 1.2 `core/ai/views.rs`: `AiImportProgress.done_bytes` / `total_bytes`
      (optional `u64`) — additive with `serde(default)`; `None` is honest
      absence, never a zeroed pair.
- [x] 1.3 `core/ai/views.rs`: `set_byte_budget` / `record_done_bytes` hold the
      pair's invariants (saturating numerator, clamped to the denominator).
- [x] 1.4 `core/ai/views_tests.rs`: budget/numerator invariants, the
      "new budget resets the numerator" rule, and wire compatibility in both
      directions.

## 2. Infra: publish both on every progress frame (PR 1)

- [x] 2.1 `infra/ai/workers.rs` (script): compute the per-chunk source bytes
      (`heading` + `\n` + `text`), publish the budget on the first frame and
      advance `done_bytes` once per completed chunk.
- [x] 2.2 `infra/ai/workers.rs` (script): publish `started_at = job.updated_at`
      — the claim stamp — on every frame of the attempt.
- [x] 2.3 `infra/ai/workers.rs` (schedule): publish the anchor; leave the byte
      pair `None` (a single extraction unit has no meaningful denominator).
- [x] 2.4 `infra/ai/merge_worker.rs`: publish the anchor on both stage frames.
- [x] 2.5 `infra/ai/worker_mutation_tests.rs`: frames of one attempt share the
      anchor; the byte numerator is monotone, never overtakes the budget, and
      the storing boundary holds it at 100 %.

## 3. Contract (PR 1)

- [x] 3.1 `backend/openapi.yaml` regenerated
      (`UPDATE_OPENAPI=1 cargo test -p api --test contract openapi_drift`).
- [x] 3.2 Dart client regenerated (`frontend-flutter/scripts/regen-client.sh`);
      the diff carries `doneBytes` / `startedAt` / `totalBytes` and nothing else.
- [x] 3.3 Crate versions bumped (`core` 0.53.0 → 0.54.0, `infra` 0.62.0 →
      0.63.0, `api` 0.52.0 → 0.53.0) + CHANGELOG entries + consumer re-pins.

## 4. Client: the pure estimator (PR 1)

- [x] 4.1 `job_eta.dart`: `aiJobProgressUnits` picks bytes over chunks and
      clamps the numerator.
- [x] 4.2 `job_eta.dart`: `estimateAiJobEta` — two-unit floor, EMA smoothing
      with a bounded per-frame step, 24 h horizon refusal, non-negative clamp.
- [x] 4.3 `job_eta.dart`: `aiJobEtaStallWindow` / `aiJobEtaStalled` (3× cadence,
      clamped to 2–30 min).
- [x] 4.4 `job_eta.dart`: `AiJobEtaCopy` + `aiJobEtaText` (coarse minutes/hours,
      range rendering, imminent, estimating, delayed) — no user-facing string in
      the file (ADR-034).
- [x] 4.5 `job_eta_test.dart`: 21 Tier-1 tests — first frame, anchor absence,
      non-positive elapsed, byte-vs-chunk preference, monotone smoothing, a 10×
      slow frame, absurd horizon, completed-job clamp, stall window edges, and
      every copy branch.

## 5. Client: the job-status line (PR 1)

- [x] 5.1 `_JobExtractionEta` in `job_status_screen.dart`: EMA carrier in
      state, a 30 s local ticker (no network), rendering only for `running`.
- [x] 5.2 The widget renders nothing and occupies no space without counters, so
      the pre-change goldens stay byte-identical.
- [x] 5.3 Six widget tests (coarse ETA, estimating, pending, no counters,
      delayed, byte-preferred).
- [x] 5.4 `app_de.arb` + `app_en.arb` keys (`aiJobEtaCalculating/Delayed/
      Imminent/Minutes/Hours/RangeMinutes/RangeHours`) + `flutter gen-l10n`.
- [x] 5.5 `frontend-flutter/CHANGELOG.md` + pubspec bump
      (`0.4.0-beta.29+121` → `0.4.0-beta.30+122`).

## 6. Apply progress (PR 2 — stacked)

- [ ] 6.1 Core: `ApplyProgress` (`applied`, `total`, `stage`, `started_at`) and
      `AiImportJob.apply_progress` (additive, `serde(default)`).
- [ ] 6.2 Migration: `ai_import.ai_import_job.apply_progress` (`JSONB`) + the
      down migration.
- [ ] 6.3 Queue port: `mark_apply_progress` (not owner-fenced — the job is
      already terminal when the apply runs) + `PgAiImportQueue` implementation
      that only writes while the job is `succeeded`.
- [ ] 6.4 `ApplyWorker::apply_script`: publish staged, throttled progress (plan
      total known up front, one write per N rows plus a final frame) — derived
      from the plan the worker already holds, never from a projection read.
- [ ] 6.5 API: `GET /ai-import/jobs/{id}/apply-events` SSE (same snapshot-first
      contract and anti-buffering headers as the job stream, same AUTHZ-GATE).
- [ ] 6.6 openapi.yaml + Dart client regeneration, contract tests.
- [ ] 6.7 Flutter: apply screen watches the apply stream while the POST is in
      flight, renders staged per-row progress and the same coarse ETA (or the
      documented indeterminate fallback).
- [ ] 6.8 Tests: the apply-progress write does not disturb the job lease or the
      terminal-state semantics; the SSE close condition is covered.
