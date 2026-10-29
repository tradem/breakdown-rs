-- SPDX-License-Identifier: AGPL-3.0
-- Copyright (C) 2024-2026 Breakdown RS Contributors
-- Co-authored-by: deepseek-v4.1-flash (opencode-go)

-- Job-row identity for the AI import list (issue #763).
--
-- Two additive, nullable columns:
--
-- * `source_file_name` — the uploaded document's own file name as the client
--   picked it, sanitized at the API edge (basename only, no control
--   characters, bounded length) and captured from the request, not from a
--   second projection lookup (CQRS boundary). NULL for every upload that
--   carried no name and for every pre-existing row: an honest absence, never a
--   fabricated or `source_handle`-derived value. `source_handle` stays an
--   opaque storage coordinate.
--
-- * `applied_episodes` — the JSONB list of target episodes a successful
--   *script* apply landed rows in (`[{id, number, name, applied_count}]`),
--   written by the apply path from the plan/target data it already holds.
--   NULL until an apply has happened; a schedule apply records none (it merges
--   onto the project's existing scenes and days and has no single target
--   episode).
--
-- No backfill on purpose: neither value can be reconstructed after the fact
-- without inventing data.
ALTER TABLE ai_import.ai_import_job
    ADD COLUMN source_file_name TEXT,
    ADD COLUMN applied_episodes JSONB;

COMMENT ON COLUMN ai_import.ai_import_job.source_file_name IS
    'Sanitized file name of the uploaded document (display metadata, issue #763); NULL when the upload carried no name or for pre-#763 rows.';

COMMENT ON COLUMN ai_import.ai_import_job.applied_episodes IS
    'Target episodes a successful script apply wrote rows into (issue #763), each with its applied row count; NULL until an apply runs.';
