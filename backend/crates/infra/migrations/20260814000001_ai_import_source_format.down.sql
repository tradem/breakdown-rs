-- SPDX-License-Identifier: AGPL-3.0
-- Copyright (C) 2024-2026 Breakdown RS Contributors
-- Co-authored-by: gpt-5.6-luna (opencode-go)

ALTER TABLE ai_import.ai_import_job
    DROP CONSTRAINT IF EXISTS ai_import_job_source_format_check,
    DROP COLUMN source_format;
