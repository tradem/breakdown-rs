-- SPDX-License-Identifier: AGPL-3.0
-- Copyright (C) 2024-2026 Breakdown RS Contributors
-- Co-authored-by: deepseek-v4.1-flash (opencode-go)

-- Revert the provider breaker (issue #871, workstream A). The job columns are
-- additive and nullable, so dropping them loses only the breaker snapshot and
-- the hold marker — no job state, no retry budget, no attempt history.
DROP INDEX IF EXISTS ai_import.idx_ai_import_job_provider_hold;
ALTER TABLE ai_import.ai_import_job
    DROP COLUMN IF EXISTS provider_hold_series_started_at,
    DROP COLUMN IF EXISTS provider_hold,
    DROP COLUMN IF EXISTS breaker_model,
    DROP COLUMN IF EXISTS breaker_provider;

DROP TABLE IF EXISTS ai_import.provider_health;
