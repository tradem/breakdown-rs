-- SPDX-License-Identifier: AGPL-3.0
-- Copyright (C) 2024-2026 Breakdown RS Contributors
-- Co-authored-by: longcat-2.0-free (opencode)

-- Issue #181, step 1 of 2: add the widened status constraint, unvalidated.
--
-- Background: a worker that could not load a job's source document or preview
-- blob previously had only `failed`/`dead_letter` available. `failed` is the
-- *retryable* state, so a permanently missing payload burned the whole retry
-- budget re-discovering its own absence; `dead_letter` conflates "the work
-- failed" with "we lost the input". `payload_unavailable` separates the two:
-- it is terminal, it is never picked up by a claim predicate (those enumerate
-- `pending`/`failed`/expired-`running` explicitly), and payload GC may sweep
-- it immediately after the retention window.
--
-- Why this is split across two migration files:
--
--   * Adding a *validated* CHECK holds ACCESS EXCLUSIVE while Postgres scans
--     every row, blocking enqueue, claim and every lifecycle write for the
--     length of the deployment.
--   * `NOT VALID` avoids the scan, but `ADD CONSTRAINT` still takes ACCESS
--     EXCLUSIVE and holds it until commit — and sqlx wraps each migration file
--     in one transaction. Validating in this same file would therefore run the
--     scan under the exclusive lock anyway, defeating the point.
--
-- So this file only adds the constraint (a fast catalog-only change) and
-- commits. `20260812000002` then validates it under SHARE UPDATE EXCLUSIVE,
-- which does not block reads or writes, and swaps the names.
--
-- The old constraint stays active throughout, so there is no window in which
-- an unknown status could be written. It rejects `payload_unavailable` until
-- step 2 drops it, which is harmless: the code emitting the new status ships
-- after both migrations.

-- Re-runnability: a partially applied attempt may have left this behind.
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
