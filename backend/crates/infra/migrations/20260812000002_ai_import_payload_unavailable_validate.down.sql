-- SPDX-License-Identifier: AGPL-3.0
-- Copyright (C) 2024-2026 Breakdown RS Contributors
-- Co-authored-by: longcat-2.0-free (opencode)

-- Rows in `payload_unavailable` have no pre-#181 equivalent that preserves
-- both "terminal" and "non-resumable". `dead_letter` is the closest: it is
-- terminal and not claimable. The remap must happen **first**, before the
-- narrowed constraint is validated, or validation would fail on exactly the
-- rows this migration exists to fold away.
UPDATE ai_import.ai_import_job
SET status = 'dead_letter'
WHERE status = 'payload_unavailable';

-- The narrowed constraint is added `NOT VALID` and validated in the same
-- transaction, which is safe *here* in a way it is not in the up direction:
-- the remap above already rewrote every offending row, so this is a rollback
-- path whose scan runs against data it just normalised. Rollbacks are
-- maintenance operations, not zero-downtime deployments; keeping both
-- statements together makes the down migration atomic, so a failure cannot
-- leave the table with a widened constraint and remapped rows.
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
