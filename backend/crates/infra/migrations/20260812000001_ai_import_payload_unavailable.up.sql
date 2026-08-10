-- SPDX-License-Identifier: AGPL-3.0
-- Copyright (C) 2024-2026 Breakdown RS Contributors
-- Co-authored-by: longcat-2.0-free (opencode)

-- Issue #181: a distinct terminal status for jobs whose durable payload is
-- gone.
--
-- Before this migration a worker that could not load a job's source document
-- or preview blob had only `failed`/`dead_letter` available. `failed` is the
-- *retryable* state, so a permanently missing payload burned the whole retry
-- budget re-discovering its own absence; `dead_letter` conflates "the work
-- failed" with "we lost the input". `payload_unavailable` separates the two:
-- it is terminal, it is never picked up by a claim predicate (those enumerate
-- `pending`/`failed`/expired-`running` explicitly), and payload GC may sweep
-- it immediately after the retention window.
--
-- The constraint is swapped **without an exclusive table scan**. Adding a
-- validated CHECK holds ACCESS EXCLUSIVE while Postgres scans every row, which
-- would block enqueue, claim and every lifecycle write for the duration of the
-- deployment. Instead the widened constraint is added `NOT VALID` (a catalog-
-- only change), validated under SHARE UPDATE EXCLUSIVE (concurrent reads and
-- writes continue), and only then does the narrow constraint go away.
--
-- The old constraint stays active for the whole swap, so there is no window in
-- which an unknown status could be written. It rejects `payload_unavailable`
-- until the final DROP, which is harmless: the code that emits the new status
-- ships after this migration.

-- Re-runnability: a partially applied attempt may have left the versioned
-- constraint behind.
ALTER TABLE ai_import.ai_import_job
    DROP CONSTRAINT IF EXISTS ai_import_job_status_check_v2;

ALTER TABLE ai_import.ai_import_job
    ADD CONSTRAINT ai_import_job_status_check_v2
    CHECK (status IN (
        'pending',
        'running',
        'succeeded',
        'failed',
        'dead_letter',
        'payload_unavailable'
    )) NOT VALID;

-- SHARE UPDATE EXCLUSIVE: does not block reads or writes.
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
