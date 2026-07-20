-- SPDX-License-Identifier: AGPL-3.0
-- Copyright (C) 2024-2026 Breakdown RS Contributors

ALTER TABLE projection_scene DROP COLUMN episode_id;
ALTER TABLE projection_scene ADD COLUMN project_id UUID NOT NULL;
CREATE INDEX IF NOT EXISTS idx_projection_scene_project_id
    ON projection_scene(project_id);
