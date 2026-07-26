-- SPDX-License-Identifier: AGPL-3.0
-- Copyright (C) 2024-2026 Breakdown RS Contributors
-- Co-authored-by: deepseek-v4-flash (opencode-go)

-- Rollback SceneShoot + ShootingDay lifecycle migrations
-- (change: add-shoot-day-execution-and-continuity).

DROP TABLE IF EXISTS projection_continuity_photo;
DROP TABLE IF EXISTS projection_scene_shoot;

ALTER TABLE projection_shooting_day DROP COLUMN IF EXISTS wrapped_at;
ALTER TABLE projection_scene DROP COLUMN IF EXISTS script_day;
