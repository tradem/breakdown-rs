-- SPDX-License-Identifier: AGPL-3.0
-- Copyright (C) 2024-2026 Breakdown RS Contributors
-- Co-authored-by: deepseek-v4-flash (opencode-go)

ALTER TABLE ai_import.ai_import_job
    DROP CONSTRAINT IF EXISTS ai_import_job_source_format_check,
    DROP COLUMN source_format;
