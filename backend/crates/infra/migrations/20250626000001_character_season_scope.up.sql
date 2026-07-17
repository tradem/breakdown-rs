-- SPDX-License-Identifier: AGPL-3.0
-- Copyright (C) 2024-2026 Breakdown RS Contributors

-- Repoint the Character projection from `project_id` to `season_id` and replace
-- the `is_extra` / `is_main_character` bool pair with a single `category` enum
-- (stored as JSONB). Pre-production: the table is empty, so NOT NULL adds are
-- safe.

ALTER TABLE projection_character DROP COLUMN project_id;
ALTER TABLE projection_character DROP COLUMN is_extra;
ALTER TABLE projection_character DROP COLUMN is_main_character;
ALTER TABLE projection_character ADD COLUMN season_id UUID NOT NULL;
ALTER TABLE projection_character ADD COLUMN category JSONB NOT NULL DEFAULT '"main_cast"';
CREATE INDEX IF NOT EXISTS idx_projection_character_season_id
    ON projection_character(season_id);
