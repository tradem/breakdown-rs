-- SPDX-License-Identifier: AGPL-3.0
-- Copyright (C) 2024-2026 Breakdown RS Contributors
-- Co-authored-by: deepseek-v4.1-flash (opencode-go)

-- Live progress of an AI-import APPLY run (issue #762).
--
-- The apply is one synchronous POST against a job that is already
-- `succeeded`, so the job status cannot carry "an apply is running" — and the
-- job SSE stream closes on the terminal frame by design. This column is the
-- run's own state: written by `ApplyWorker::apply_script` from the plan it
-- already holds (never from a projection read), cleared when the run ends.
--
-- Payload shape (core `ApplyProgress`):
--
--   {"stage": "applying" | "finalizing",
--    "applied": 12, "total": 57,
--    "started_at": "2026-11-02T10:00:00Z",
--    "updated_at": "2026-11-02T10:00:31Z"}
--
-- `NULL` means "no apply is in flight": every pre-#762 row, a preview nobody
-- applied yet, and a finished run. `updated_at` inside the payload is what lets
-- the stream recognise a run whose process died (a stale payload is treated as
-- finished instead of holding a connection open forever).
--
-- No backfill: a past apply's progress cannot be reconstructed, so it stays
-- NULL and the wire renders an honest `null`.
ALTER TABLE ai_import.ai_import_job
    ADD COLUMN apply_progress JSONB;

COMMENT ON COLUMN ai_import.ai_import_job.apply_progress IS
    'Live progress of an in-flight apply run (issue #762): stage, applied/total rows, started_at, updated_at; NULL when no apply is running.';
