-- no-transaction
-- SPDX-License-Identifier: AGPL-3.0
-- Copyright (C) 2024-2026 Breakdown RS Contributors
-- Co-authored-by: longcat-2.0-free (opencode)

-- Issue #177 (CodeRabbit review): the claim predicate now also scans expired
-- `running` leases; keep that path indexed alongside the existing
-- (status, next_attempt_at, created_at) index.
--
-- This is a separate migration on purpose. `CREATE INDEX CONCURRENTLY` must
-- not run inside a transaction block, and sqlx sends a migration file as a
-- single multi-statement simple query, which Postgres implicitly wraps in a
-- transaction — so `-- no-transaction` alone is not enough when the file also
-- contains other statements. Isolating the index build in its own
-- single-statement, `-- no-transaction` migration is what actually keeps the
-- build from blocking writes to `ai_import.ai_import_job`.
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_ai_import_job_lease
    ON ai_import.ai_import_job (status, lease_expires_at);
