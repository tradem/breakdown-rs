-- SPDX-License-Identifier: AGPL-3.0
-- Copyright (C) 2024-2026 Breakdown RS Contributors
-- Co-authored-by: deepseek-v4-flash (opencode-go)

-- Roll back to the NOT NULL contract: backfill rows that were recorded as
-- NotApplied (NULL) with 0, then restore NOT NULL + DEFAULT 0.
UPDATE ai_import.ai_import_job
SET edit_distance = 0
WHERE edit_distance IS NULL;

ALTER TABLE ai_import.ai_import_job
    ALTER COLUMN edit_distance SET DEFAULT 0,
    ALTER COLUMN edit_distance SET NOT NULL;
