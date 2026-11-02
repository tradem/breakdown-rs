-- SPDX-License-Identifier: AGPL-3.0
-- Copyright (C) 2024-2026 Breakdown RS Contributors
-- Co-authored-by: deepseek-v4.1-flash (opencode-go)

-- Revert issue #800: drop the apply-run identity columns. The progress payload
-- column from #762 stays.
ALTER TABLE ai_import.ai_import_job
    DROP COLUMN IF EXISTS apply_run_seq,
    DROP COLUMN IF EXISTS apply_run_id;
