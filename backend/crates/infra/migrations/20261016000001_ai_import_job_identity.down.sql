-- SPDX-License-Identifier: AGPL-3.0
-- Copyright (C) 2024-2026 Breakdown RS Contributors
-- Co-authored-by: deepseek-v4.1-flash (opencode-go)

-- Revert issue #763: drop the jobs-list identity columns.
ALTER TABLE ai_import.ai_import_job
    DROP COLUMN IF EXISTS source_file_name,
    DROP COLUMN IF EXISTS applied_episodes;
