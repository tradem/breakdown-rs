-- SPDX-License-Identifier: AGPL-3.0
-- Copyright (C) 2024-2026 Breakdown RS Contributors
-- Co-authored-by: longcat-2.0-free (opencode)

-- Rows already in `payload_unavailable` have no pre-#181 equivalent that
-- preserves both "terminal" and "non-resumable". `dead_letter` is the closest:
-- it is terminal and not claimable. Fold them there before restoring the
-- narrower constraint, otherwise the ADD CONSTRAINT below fails.
UPDATE ai_import.ai_import_job
SET status = 'dead_letter'
WHERE status = 'payload_unavailable';

ALTER TABLE ai_import.ai_import_job
    DROP CONSTRAINT IF EXISTS ai_import_job_status_check;

ALTER TABLE ai_import.ai_import_job
    ADD CONSTRAINT ai_import_job_status_check
    CHECK (status IN ('pending', 'running', 'succeeded', 'failed', 'dead_letter'));
