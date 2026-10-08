-- SPDX-License-Identifier: AGPL-3.0
-- Copyright (C) 2024-2026 Breakdown RS Contributors
-- Co-authored-by: space-bunny (opencode-go)

-- Roll back the projection-column spelling of the `SeriesId` → `ProjectId`
-- rename (issue #599, ADR-035 S1). The rename is a pure spelling change, so
-- the inverse is exact: no row was rewritten and no index had to be rebuilt.

ALTER TABLE projection_audit
    RENAME COLUMN project_id TO series_id;
ALTER INDEX IF EXISTS idx_projection_audit_project
    RENAME TO idx_projection_audit_series;

ALTER TABLE projection_episode
    RENAME COLUMN project_id TO series_id;
ALTER INDEX IF EXISTS idx_projection_episode_project_id
    RENAME TO idx_projection_episode_series_id;
ALTER INDEX IF EXISTS idx_projection_episode_project_number
    RENAME TO idx_projection_episode_series_number;

ALTER TABLE projection_block
    RENAME COLUMN project_id TO series_id;
ALTER INDEX IF EXISTS idx_projection_block_project_id
    RENAME TO idx_projection_block_series_id;
ALTER INDEX IF EXISTS idx_projection_block_project_number
    RENAME TO idx_projection_block_series_number;

ALTER TABLE projection_season
    RENAME COLUMN project_id TO series_id;
ALTER INDEX IF EXISTS idx_projection_season_project_id
    RENAME TO idx_projection_season_series_id;
ALTER INDEX IF EXISTS idx_projection_season_project_number
    RENAME TO idx_projection_season_series_number;