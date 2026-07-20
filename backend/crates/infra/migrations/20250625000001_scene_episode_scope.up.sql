-- SPDX-License-Identifier: AGPL-3.0
-- Copyright (C) 2024-2026 Breakdown RS Contributors

-- Repoint the Scene projection from `project_id` to `episode_id`.
-- A Scene is scoped to exactly one Episode (work-unit scope), not to a
-- production-level Project. Pre-production: the table is empty, so the
-- NOT NULL add is safe.

ALTER TABLE projection_scene DROP COLUMN project_id;
ALTER TABLE projection_scene ADD COLUMN episode_id UUID NOT NULL;
CREATE INDEX IF NOT EXISTS idx_projection_scene_episode_id
    ON projection_scene(episode_id);
