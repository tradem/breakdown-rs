-- SPDX-License-Identifier: AGPL-3.0
-- Copyright (C) 2024-2026 Breakdown RS Contributors
-- Co-authored-by: deepseek-v4-flash (opencode-go)

-- Issue #171: `edit_distance` becomes nullable so jobs that never reach apply
-- are recorded as NULL instead of a misleading `0`. The inline CHECK
-- (edit_distance >= 0) already passes for NULL (NULL >= 0 is not FALSE), so no
-- CHECK change is required. Applied zero-edit outcomes keep `edit_distance = 0`.
ALTER TABLE ai_import.ai_import_job
    ALTER COLUMN edit_distance DROP NOT NULL,
    ALTER COLUMN edit_distance DROP DEFAULT;
