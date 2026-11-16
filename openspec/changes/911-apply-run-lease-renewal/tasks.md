<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3 (neuralwatt) -->

# Tasks — issue #911 (apply-run lease renewal)

## 1. Port

- [x] 1.1 `AiImportQueue::renew_apply_run(id, run_id) -> Result<bool, DomainError>` with an
      optimistic `Ok(true)` default (slot-less adapters) and the "false = slot moved on"
      contract documented next to `record_run_telemetry`.

## 2. Postgres adapter

- [x] 2.1 `PgAiImportQueue::renew_apply_run`: `UPDATE … SET apply_claim_at = now()
      WHERE id = $1 AND apply_run_id = $2`, verdict from `rows_affected()`.
- [x] 2.2 Document why nothing else is written (no payload / `apply_run_seq` /
      `updated_at` / `pg_notify`).

## 3. Renewal loop

- [x] 3.1 `infra::ai::with_apply_run_lease(queue, job_id, run_id, window, run)` — the run's
      own future polled against a ticker at `renewal_interval(window)`; `select!`, so the
      renewal is cancelled with the run.
- [x] 3.2 `infra::ai::apply_run_lease_window()` = `ApplyProgress::STALE_AFTER` (one
      definition for steal predicate and cadence).
- [x] 3.3 Stop on `false` (log + stop renewing, still return the run's outcome), keep
      renewing on a transient error (the window has two more intervals of headroom).
- [x] 3.4 Re-export from `infra::ai`.

## 4. Runner wiring

- [x] 4.1 `ApplyRunner::run_claimed` executes under the lease (both branches).
- [x] 4.2 `run_claimed` docs state the schedule-apply motivation and that the renewal dies
      with the run.

## 5. Tests

- [x] 5.1 `crates/infra/src/ai/heartbeat.rs`: scripted-fake lease tests (cadence, `false`
      stops, transient keeps going, zero window disables, window == `STALE_AFTER`).
- [x] 5.2 `crates/integration-tests/tests/ai_import_job_progress.rs`:
      `renewing_a_claim_keeps_a_silent_run_alive` (renewed owner is not stealable, refusal
      reports the refreshed silence) and `a_taken_over_runs_renewal_reports_false` (the
      fence after a takeover).

## 6. Documentation

- [x] 6.1 `backend/.github/instructions/ai-import.instructions.md` — "rules that must not
      drift" gains the renewal rule.
- [x] 6.2 `openspec/changes/ai-import-durable-apply-run/design.md` — the accepted-overlap
      risk names #911 as the closure for the live-owner case.

## 7. Release mechanics

- [x] 7.1 Version bumps: `core` 0.69.0 → 0.70.0, `infra` 0.80.0 → 0.81.0,
      `api` 0.68.0 → 0.69.0 (additive port method + new infra entry point + runner change).
