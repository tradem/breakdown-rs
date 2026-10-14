-- SPDX-License-Identifier: AGPL-3.0
-- Copyright (C) 2024-2026 Breakdown RS Contributors
-- Co-authored-by: deepseek-v4.1-flash (neuralwatt)

ALTER TABLE ai_import.ai_import_job_attempt
    DROP COLUMN IF EXISTS error_code;
