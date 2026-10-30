-- SPDX-License-Identifier: AGPL-3.0
-- Copyright (C) 2024-2026 Breakdown RS Contributors
-- Co-authored-by: glm-5.3 (neuralwatt)

-- Import-target snapshot for the AI import job (issue #771).
--
-- A job's authoritative write target is `block_id` (the block in the required
-- `X-Active-Block` header); the season follows from that block. Nothing on the
-- wire named the target, so the reported defect could only be observed after
-- the fact: an import started from a freshly created season landed all of its
-- episodes in the *previously* active season's block, and no row said where it
-- had been meant to go.
--
-- Three additive, nullable columns snapshot the target resolved at the API
-- edge from the read models (the block's owning season + both production-global
-- numbers). They are display/attribution metadata, never a second write
-- target: the apply path keeps pinning itself to `block_id`.
--
-- No backfill on purpose: a pre-#771 row's intended target cannot be
-- reconstructed without inventing data, so it stays NULL and the wire renders
-- an honest `null`.
ALTER TABLE ai_import.ai_import_job
    ADD COLUMN target_season_id UUID,
    ADD COLUMN target_season_number INT,
    ADD COLUMN target_block_number INT;

COMMENT ON COLUMN ai_import.ai_import_job.target_season_id IS
    'Season owning the job''s block at dispatch time (issue #771); NULL for pre-#771 rows.';

COMMENT ON COLUMN ai_import.ai_import_job.target_season_number IS
    'Production-global number of the target season at dispatch time (issue #771); NULL when unresolved.';

COMMENT ON COLUMN ai_import.ai_import_job.target_block_number IS
    'Production-global number of the target block at dispatch time (issue #771); NULL when unresolved.';
