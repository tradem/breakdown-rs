-- SPDX-License-Identifier: AGPL-3.0
-- Copyright (C) 2024-2026 Breakdown RS Contributors
-- Co-authored-by: glm-5.3-flash (opencode-go)

-- Roll back the costume-level category columns (issue #543).

ALTER TABLE projection_costume
    DROP COLUMN category_id,
    DROP COLUMN category_name;
