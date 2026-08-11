-- SPDX-License-Identifier: AGPL-3.0
-- Copyright (C) 2024-2026 Breakdown RS Contributors
-- Co-authored-by: deepseek-v4-flash (opencode-go)

-- Issue #221: persist the declared source document format so the schedule
-- worker can route CSV natively and PDF/plain-text through the LLM extraction
-- path. Script jobs are always PDF; legacy schedule rows were all processed
-- through the native CSV parser before this change, so they backfill to 'csv'
-- (preserving their previous routing exactly).
ALTER TABLE ai_import.ai_import_job
    ADD COLUMN source_format TEXT;

UPDATE ai_import.ai_import_job
SET source_format = 'csv'
WHERE document_kind = 'schedule';

UPDATE ai_import.ai_import_job
SET source_format = 'pdf'
WHERE document_kind = 'script';

ALTER TABLE ai_import.ai_import_job
    ALTER COLUMN source_format SET NOT NULL,
    ADD CONSTRAINT ai_import_job_source_format_check
        CHECK (source_format IN ('csv', 'pdf', 'plain_text'));
