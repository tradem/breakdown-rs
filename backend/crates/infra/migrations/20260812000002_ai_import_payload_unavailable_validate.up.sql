-- SPDX-License-Identifier: AGPL-3.0
-- Copyright (C) 2024-2026 Breakdown RS Contributors
-- Co-authored-by: longcat-2.0-free (opencode)

-- Issue #181, step 2 of 2: validate the widened constraint and swap it in.
--
-- `20260812000001` added `ai_import_job_status_check_v2` as `NOT VALID` and
-- committed, releasing the ACCESS EXCLUSIVE lock that `ADD CONSTRAINT` takes.
-- The scan below therefore runs in its own transaction under SHARE UPDATE
-- EXCLUSIVE, which does not block concurrent reads or writes — job enqueue,
-- claim and lifecycle writes continue during the deployment.
--
-- Only after the widened constraint is proven valid does the narrow one go
-- away, so the column is never unconstrained.
ALTER TABLE ai_import.ai_import_job
    VALIDATE CONSTRAINT ai_import_job_status_check_v2;

ALTER TABLE ai_import.ai_import_job
    DROP CONSTRAINT IF EXISTS ai_import_job_status_check;

ALTER TABLE ai_import.ai_import_job
    RENAME CONSTRAINT ai_import_job_status_check_v2 TO ai_import_job_status_check;

COMMENT ON COLUMN ai_import.ai_import_job.status IS
    'Operational lifecycle. `failed` is retryable (backoff via next_attempt_at); '
    '`succeeded`, `dead_letter` and `payload_unavailable` are terminal. '
    '`payload_unavailable` means the durable source/preview payload is gone, so '
    'the job is non-resumable (issue #181).';
