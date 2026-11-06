-- SPDX-License-Identifier: AGPL-3.0
-- Copyright (C) 2024-2026 Breakdown RS Contributors
-- Co-authored-by: glm-5.3 (neuralwatt)

-- Drop the denormalized applied-episode summary (issue #864).
--
-- The column was written by `apply_ai_import` AFTER `ApplyWorker::apply_script`
-- returned (migration 20261016000001, issue #763). Two independent reasons left
-- it NULL although rows had been committed:
--
--  1. cancel-sensitivity — a client that dropped or retried the request
--     cancelled the handler future after the scene rows committed and before
--     the summary write, and nothing retried it;
--  2. best-effort by design — a failing write was a warning, so "no summary"
--     was indistinguishable from "no apply ever ran".
--
-- The summary is now derived at the read edge from the durable apply mappings
-- (`projection_ai_import_mapping` scene rows joined to `projection_scene` and
-- `projection_episode`), which cannot be lost by a cancellation and is also
-- more accurate: a row reconciled onto an EXISTING scene is attributed to that
-- scene's episode rather than to the episode the request named.
--
-- Dropping the column is safe and lossless: every value it could hold is a
-- function of the mapping rows plus the scenes they point at, and both survive
-- exactly as long as the job (`delete_terminal` removes them together).
ALTER TABLE ai_import.ai_import_job
    DROP COLUMN IF EXISTS applied_episodes;
