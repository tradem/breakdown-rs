-- SPDX-License-Identifier: AGPL-3.0
-- Copyright (C) 2024-2026 Breakdown RS Contributors
-- Co-authored-by: longcat-2.0-free (opencode)

DROP INDEX IF EXISTS ai_import.idx_ai_import_job_lease;

ALTER TABLE ai_import.ai_import_job
    DROP COLUMN IF EXISTS lease_expires_at,
    DROP COLUMN IF EXISTS worker_id;
