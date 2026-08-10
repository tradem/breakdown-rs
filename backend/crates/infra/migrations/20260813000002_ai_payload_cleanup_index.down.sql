-- no-transaction
-- SPDX-License-Identifier: AGPL-3.0
-- Copyright (C) 2024-2026 Breakdown RS Contributors
-- Co-authored-by: longcat-2.0-free (opencode)

-- Dropped concurrently for the same reason it is built concurrently: a plain
-- DROP INDEX takes an ACCESS EXCLUSIVE lock on the job table.
DROP INDEX CONCURRENTLY IF EXISTS ai_import.idx_ai_import_job_retention;
