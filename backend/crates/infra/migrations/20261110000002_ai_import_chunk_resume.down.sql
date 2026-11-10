-- SPDX-License-Identifier: AGPL-3.0
-- Copyright (C) 2024-2026 Breakdown RS Contributors
-- Co-authored-by: deepseek-v4.1-flash (opencode-go)

-- Revert chunk-level resume (issue #871, workstream B). The chunk rows are
-- derived work, so dropping them loses only the ability to resume — never a
-- preview, a job state or a retry budget.
DROP TABLE IF EXISTS ai_import.ai_import_job_chunk;
ALTER TABLE ai_import.ai_import_job
    DROP COLUMN IF EXISTS extraction_key_components,
    DROP COLUMN IF EXISTS extraction_key;
