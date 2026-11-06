-- SPDX-License-Identifier: AGPL-3.0
-- Copyright (C) 2024-2026 Breakdown RS Contributors
-- Co-authored-by: deepseek-v4.1-flash (opencode-go)

-- The import target may name a season WITHOUT a block (issue #829).
--
-- An upload is now allowed to omit `X-Active-Block` and declare only its
-- season: the job starts block-less (`block_id IS NULL`) with its target season
-- already known, and the target block is attached later via
-- `PUT /v1/ai-import/jobs/{id}/target`. The block number therefore stops being
-- written "together with" the season pair and becomes optional on its own.
--
-- No schema change: all three `target_*` columns were nullable from the start
-- (migration 20261101000001); only the documented meaning of the block number
-- widens. The season pair keeps its all-or-nothing rule — a target without a
-- season is still not a target.
COMMENT ON COLUMN ai_import.ai_import_job.target_block_number IS
    'Production-global number of the target block: NULL when unresolved at dispatch, and for a block-less upload (issue #829) until the target is attached.';
