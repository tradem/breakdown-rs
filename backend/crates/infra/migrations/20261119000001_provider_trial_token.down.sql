-- SPDX-License-Identifier: AGPL-3.0
-- Copyright (C) 2024-2026 Breakdown RS Contributors
-- Co-authored-by: deepseek-v4.1-flash (opencode-go)

DROP INDEX IF EXISTS ai_import.idx_provider_health_trial_job;

ALTER TABLE ai_import.provider_health
    DROP COLUMN IF EXISTS trial_job_id;
