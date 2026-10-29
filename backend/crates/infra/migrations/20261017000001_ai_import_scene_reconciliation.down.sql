-- SPDX-License-Identifier: AGPL-3.0
-- Copyright (C) 2024-2026 Breakdown RS Contributors
-- Co-authored-by: deepseek-v4.1-flash (opencode-go)

-- Revert issue #758: drop the script scene reconciliation counters.
ALTER TABLE ai_import.ai_import_job
    DROP CONSTRAINT IF EXISTS ai_import_job_scenes_nonnegative;

ALTER TABLE ai_import.ai_import_job
    DROP COLUMN IF EXISTS scenes_detected,
    DROP COLUMN IF EXISTS scenes_extracted,
    DROP COLUMN IF EXISTS scenes_synthesized;
