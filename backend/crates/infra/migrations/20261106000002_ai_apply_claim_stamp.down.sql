-- SPDX-License-Identifier: AGPL-3.0
-- Copyright (C) 2024-2026 Breakdown RS Contributors
-- Co-authored-by: deepseek-v4.1-flash (opencode-go)

-- Revert the owner-scoped claim stamp (issue #863 review). The run identity and
-- progress columns from #762/#800 stay; the steal predicate's unpublished
-- branch returns to the row's `updated_at`.
ALTER TABLE ai_import.ai_import_job
    DROP COLUMN IF EXISTS apply_claim_at;
