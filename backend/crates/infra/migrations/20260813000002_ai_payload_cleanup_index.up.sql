-- no-transaction
-- SPDX-License-Identifier: AGPL-3.0
-- Copyright (C) 2024-2026 Breakdown RS Contributors
-- Co-authored-by: longcat-2.0-free (opencode)

-- Issue #206: index the retention sweep's access path.
--
-- The sweep matches `status IN ('succeeded','dead_letter','payload_unavailable')
-- AND updated_at < cutoff ORDER BY updated_at LIMIT n`. The existing
-- `idx_ai_import_job_claim (status, next_attempt_at, created_at)` serves the
-- *claim* predicate and cannot satisfy this ordering, so the sweep fell back
-- to a full scan of the job table. That was tolerable only while the sweep
-- re-read the same parked head of the queue; now that marks let it advance,
-- it must be able to walk the retention frontier cheaply.
--
-- Partial on the terminal statuses: the runnable rows are the hot,
-- frequently-updated ones, and excluding them keeps the index small and its
-- write amplification off the claim path.
--
-- Known cost profile, measured rather than assumed: because cleanup marks live
-- in a second table, the scan still walks the already-cleaned prefix in
-- `updated_at` order before reaching the frontier of uncleaned jobs. At 200k
-- terminal jobs with 150k marks that is ~85 ms for a full 1000-row batch. It
-- grows linearly with the number of retained terminal jobs, which is fine for
-- an hourly sweep and orders of magnitude below the S3 round-trips this change
-- removes; if job rows are ever retained into the millions *and* the sweep
-- becomes hot, the fix is to prune terminal job rows, not to widen this index.
--
-- A separate `-- no-transaction`, single-statement migration for the reason
-- spelled out in `20260809000002`: `CREATE INDEX CONCURRENTLY` must not run
-- inside a transaction block, and sqlx wraps a multi-statement migration file
-- in one.
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_ai_import_job_retention
    ON ai_import.ai_import_job (updated_at)
    WHERE status IN ('succeeded', 'dead_letter', 'payload_unavailable');
