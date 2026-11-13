-- SPDX-License-Identifier: AGPL-3.0
-- Copyright (C) 2024-2026 Breakdown RS Contributors
-- Co-authored-by: glm-5.3 (neuralwatt)

-- Revert the durable apply-run slot (issue #899). The run identity, claim stamp
-- and progress columns from #762/#800/#863 stay: they describe a live run's
-- payload, which the request-bound path also publishes.
DROP INDEX IF EXISTS ai_import.idx_ai_import_job_apply_requested;

ALTER TABLE ai_import.ai_import_job
    DROP CONSTRAINT IF EXISTS ai_import_job_apply_state_check;

ALTER TABLE ai_import.ai_import_job
    DROP COLUMN IF EXISTS apply_result,
    DROP COLUMN IF EXISTS apply_request,
    DROP COLUMN IF EXISTS apply_state;
