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
ALTER TABLE ai_import.ai_import_job
    DROP CONSTRAINT IF EXISTS ai_import_job_status_check;

ALTER TABLE ai_import.ai_import_job
    ADD CONSTRAINT ai_import_job_status_check
    CHECK (status IN (
        'pending',
        'running',
        'succeeded',
        'failed',
        'dead_letter',
        'payload_unavailable'
    ));

COMMENT ON COLUMN ai_import.ai_import_job.status IS
    'Operational lifecycle. `failed` is retryable (backoff via next_attempt_at); '
    '`succeeded`, `dead_letter` and `payload_unavailable` are terminal. '
    '`payload_unavailable` means the durable source/preview payload is gone, so '
    'the job is non-resumable (issue #181).';
