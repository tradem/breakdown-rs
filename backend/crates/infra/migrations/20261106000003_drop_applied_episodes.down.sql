-- SPDX-License-Identifier: AGPL-3.0
-- Copyright (C) 2024-2026 Breakdown RS Contributors
-- Co-authored-by: glm-5.3 (neuralwatt)

-- Revert issue #864: restore the denormalized summary column.
--
-- Re-added as a nullable column WITHOUT a backfill: the value is derived at the
-- read edge since this change, so a pre-revert row legitimately holds NULL and
-- nothing has to be invented to make the previous build work.
ALTER TABLE ai_import.ai_import_job
    ADD COLUMN IF NOT EXISTS applied_episodes JSONB;

COMMENT ON COLUMN ai_import.ai_import_job.applied_episodes IS
    'Target episodes a successful script apply wrote rows into (issue #763), each with its applied row count; NULL until an apply runs. Superseded by the read-edge derivation of issue #864.';
