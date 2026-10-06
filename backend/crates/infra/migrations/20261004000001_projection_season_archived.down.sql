-- SPDX-License-Identifier: AGPL-3.0
-- Copyright (C) 2024-2026 Breakdown RS Contributors
-- Co-authored-by: glm-5.3-flash (opencode-go)

-- Roll back the season lifecycle flag (issue #533).

ALTER TABLE projection_season
    DROP COLUMN archived;
