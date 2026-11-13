-- SPDX-License-Identifier: AGPL-3.0
-- Copyright (C) 2024-2026 Breakdown RS Contributors
-- Co-authored-by: glm-5.3 (neuralwatt)

-- Keep the outcome attributable after the run that produced it is gone
-- (review of #899).
--
-- `apply_run_id` is *ownership*: the run that currently holds the single-flight
-- slot. The terminal transition (`complete_apply_run` / `fail_apply_run`)
-- clears it, because a finished run must free the slot immediately — otherwise
-- a re-apply would have to wait out the silence window. With the id cleared,
-- however, the terminal stream frame and `GET /jobs/{id}` could no longer say
-- *which* run produced the persisted `apply_result`. A client that dispatched
-- run A and re-attached after run B had already replaced it therefore had no
-- way to tell B's counters from its own, and would report a stranger's import
-- as its own.
--
-- So attribution gets its own column instead of overloading ownership:
--
--   * written by the same fenced statement that writes `apply_result`
--     (`WHERE id = $1 AND apply_run_id = $2`), so a displaced run cannot
--     attribute its outcome to the new owner's slot;
--   * cleared when a NEW run is requested (a new request means a new outcome
--     will overwrite this one);
--   * read as the run identity of the outcome — while a run is live the
--     ownership column answers that question, which is what the reader falls
--     back to.
--
-- NULL for every existing row: their outcome (if any) predates the attribution
-- and is honestly "unknown origin" rather than a guessed run id.
ALTER TABLE ai_import.ai_import_job
    ADD COLUMN apply_result_run_id UUID;

COMMENT ON COLUMN ai_import.ai_import_job.apply_result_run_id IS
    'The run that produced the persisted apply_result (issue #899). Distinct from apply_run_id (live ownership): it survives the terminal transition so a client can attribute the outcome it reads.';
