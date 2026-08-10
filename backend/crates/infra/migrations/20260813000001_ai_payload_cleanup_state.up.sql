-- SPDX-License-Identifier: AGPL-3.0
-- Copyright (C) 2024-2026 Breakdown RS Contributors
-- Co-authored-by: longcat-2.0-free (opencode)

-- Issue #206: per-payload cleanup state for the AI payload GC sweep.
--
-- Before this table the sweep selected the oldest `batch_size` terminal jobs
-- on *every* run and recorded no completion anywhere. Deletions are
-- idempotent, so nothing was corrupted — but the same jobs were re-selected
-- forever: the S3 round-trips were repeated, the run-history counters counted
-- the same deletions again on each pass, and any job past the `LIMIT`
-- starved behind a permanently-parked head of the queue.
--
-- Why a table rather than a column on `ai_import_job`:
--
--   * A job owns **two independent payloads** (`source_handle`, which is NOT
--     NULL, and `preview_handle`, which is set only by `mark_succeeded`). A
--     partial sweep — source deleted, preview deletion hit a 503 — must be
--     able to retry exactly the half that failed. A single `cleanup_state`
--     flag cannot express that; two columns could, but would grow the hot
--     queue row (claim/lease/telemetry writes) for a cold retention concern.
--   * The row is an audit record, not job state: it names the handle that was
--     actually deleted and the sweep that did it, which is what an operator
--     needs when reconciling Garage against the queue.
--
-- `updated_at` on the job row is deliberately **not** touched by a sweep: it
-- is the retention clock *and* the sweep's `ORDER BY` key, so marking cleanup
-- there would reset the very window it measures.
CREATE TABLE ai_import.ai_payload_cleanup (
    job_id          UUID NOT NULL
                    REFERENCES ai_import.ai_import_job (id) ON DELETE CASCADE,
    -- 'source' | 'preview'. Enumerated rather than free text so a typo in the
    -- adapter cannot silently create a third kind that the anti-join then
    -- never matches (which would re-open the re-processing bug).
    payload_kind    TEXT NOT NULL CHECK (payload_kind IN ('source', 'preview')),
    -- The handle as it existed when the deletion ran. Kept for reconciliation:
    -- a job row can only ever be read for its *current* handle, so without
    -- this the audit trail could not name the object that was removed.
    handle          TEXT NOT NULL,
    -- The sweep that recorded this mark. Intentionally **not** a foreign key
    -- to `projection_ai_payload_gc_run`: that history row is written after the
    -- deletions complete (it carries `finished_at`), so an FK would either
    -- reject every mark or force a two-phase write for no benefit.
    run_id          UUID NOT NULL,
    cleaned_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (job_id, payload_kind)
);

COMMENT ON TABLE ai_import.ai_payload_cleanup IS
    'Per-payload GC completion marks; the anti-join that keeps a swept job from being swept again (issue #206).';
