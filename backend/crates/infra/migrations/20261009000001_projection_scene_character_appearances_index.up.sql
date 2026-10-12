-- SPDX-License-Identifier: AGPL-3.0
-- Copyright (C) 2024-2026 Breakdown RS Contributors
-- Co-authored-by: deepseek-v4.1-flash (neuralwatt)

-- Supporting index for the per-character appearances read model (issue #621):
-- `GET /v1/characters/{id}/appearances` filters `projection_scene_character`
-- by `character_id` and joins `projection_scene` for `scene_number`/`summary`,
-- ordered by `scene_number`.
--
-- A literal composite `(character_id, scene_number)` index is impossible across
-- the two tables: `scene_number` lives on `projection_scene`, not on
-- `projection_scene_character`. This covering index supplies both join keys
-- (`character_id` filter, `scene_id` probe) so the filter + join resolves
-- index-only; the script-order sort then runs over the (small) per-character
-- result set. It complements the single-column
-- `idx_projection_scene_character_character_id`, which is kept for the
-- existing scene-side reads.
CREATE INDEX IF NOT EXISTS idx_projection_scene_character_character_scene
    ON projection_scene_character(character_id, scene_id);
