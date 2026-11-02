-- SPDX-License-Identifier: AGPL-3.0
-- Copyright (C) 2024-2026 Breakdown RS Contributors
-- Co-authored-by: deepseek-v4.1-flash (opencode-go)

-- Run identity + liveness of an AI-import APPLY run (issue #800).
--
-- The apply-run progress slot added by `20261103000001` is keyed by job id
-- only, which made four windows indistinguishable:
--
--   * two accepted applies of one `succeeded` job overwrote each other's
--     counters, and the first run to finish cleared the slot out from under the
--     still-running one;
--   * a run that started and cleared between two stream re-reads left no trace
--     at all, so the stream could not tell "no run yet" from "a run already
--     ended" and closed without its documented final frame;
--   * a clear could not be conditioned on the run that owned the payload, so a
--     deferred (client-disconnect) clear risked removing a NEWER run's progress.
--
-- Two columns close that gap:
--
-- `apply_run_id` is the run that currently OWNS the slot. It is written by the
-- claim (`AiImportQueue::claim_apply_run`), every progress write and the clear
-- are conditional on it, and it is released together with `apply_progress`.
-- A run that lost the slot (its claim went stale and was stolen) therefore
-- cannot publish or clear anything.
--
-- `apply_run_seq` is a monotonic counter bumped on every claim and NEVER
-- cleared. That is the start/completion signal that survives a re-read: a
-- non-zero delta since the stream's subscribe-time baseline proves a run
-- happened even when its payload was already gone.
--
-- No backfill: a pre-#800 run cannot be reconstructed, so both columns start
-- NULL / 0 and the existing payload (if any) simply has no owner — it can be
-- read and rendered, but never cleared by a run that does not own it.
ALTER TABLE ai_import.ai_import_job
    ADD COLUMN apply_run_id UUID,
    ADD COLUMN apply_run_seq BIGINT NOT NULL DEFAULT 0;

COMMENT ON COLUMN ai_import.ai_import_job.apply_run_id IS
    'The apply run that currently owns apply_progress (issue #800); every run-scoped write and the clear are conditional on it, and it is released with the payload.';

COMMENT ON COLUMN ai_import.ai_import_job.apply_run_seq IS
    'Monotonic apply-run counter (issue #800): bumped on every claim, never cleared, so a run that started and ended between two reads is still provable.';
