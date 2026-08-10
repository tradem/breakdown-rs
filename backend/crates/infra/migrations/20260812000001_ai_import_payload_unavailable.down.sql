-- SPDX-License-Identifier: AGPL-3.0
-- Copyright (C) 2024-2026 Breakdown RS Contributors
-- Co-authored-by: longcat-2.0-free (opencode)

-- Rows already in `payload_unavailable` have no pre-#181 equivalent that
-- preserves both "terminal" and "non-resumable". `dead_letter` is the closest:
-- it is terminal and not claimable. The remap must happen **first**, before
-- the narrowed constraint is validated, or validation would fail on exactly
-- the rows this migration exists to fold away.
UPDATE ai_import.ai_import_job
SET status = 'dead_letter'
WHERE status = 'payload_unavailable';

-- Same no-exclusive-scan swap as the up migration: add `NOT VALID`, validate
-- under SHARE UPDATE EXCLUSIVE, then drop and rename. See the up migration for
-- the full rationale.
ALTER TABLE ai_import.ai_import_job
    DROP CONSTRAINT IF EXISTS ai_import_job_status_check_v1;

ALTER TABLE ai_import.ai_import_job
    ADD CONSTRAINT ai_import_job_status_check_v1
    CHECK (status IN ('pending', 'running', 'succeeded', 'failed', 'dead_letter'))
    NOT VALID;

ALTER TABLE ai_import.ai_import_job
    VALIDATE CONSTRAINT ai_import_job_status_check_v1;

ALTER TABLE ai_import.ai_import_job
    DROP CONSTRAINT IF EXISTS ai_import_job_status_check;

ALTER TABLE ai_import.ai_import_job
    RENAME CONSTRAINT ai_import_job_status_check_v1 TO ai_import_job_status_check;
