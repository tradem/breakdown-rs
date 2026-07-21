-- SPDX-License-Identifier: AGPL-3.0
-- Copyright (C) 2024-2026 Breakdown RS Contributors

DROP TABLE IF EXISTS projection_scene_shooting_day;
DROP TABLE IF EXISTS projection_shooting_day;
ALTER TABLE projection_scene DROP COLUMN IF EXISTS summary;
