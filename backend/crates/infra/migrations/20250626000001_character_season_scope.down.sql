-- SPDX-License-Identifier: AGPL-3.0
-- Copyright (C) 2024-2026 Breakdown RS Contributors

ALTER TABLE projection_character DROP COLUMN season_id;
ALTER TABLE projection_character DROP COLUMN category;
ALTER TABLE projection_character ADD COLUMN project_id UUID NOT NULL;
ALTER TABLE projection_character ADD COLUMN is_extra BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE projection_character ADD COLUMN is_main_character BOOLEAN NOT NULL DEFAULT FALSE;
CREATE INDEX IF NOT EXISTS idx_projection_character_project_id
    ON projection_character(project_id);
