-- SPDX-License-Identifier: AGPL-3.0
-- Copyright (C) 2024-2026 Breakdown RS Contributors
-- Co-authored-by: gpt-5.6-luna (pi)
-- Co-authored-by: longcat-2.0-free (opencode)

-- Reverse of the up migration: drop the permit link column.
ALTER TABLE ai_import.ai_import_job
    DROP COLUMN IF EXISTS permit_id;
