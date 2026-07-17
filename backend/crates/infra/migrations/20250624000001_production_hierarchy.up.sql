-- SPDX-License-Identifier: AGPL-3.0
-- Copyright (C) 2024-2026 Breakdown RS Contributors

-- Production-hierarchy projections for the v1 four-level hierarchy:
-- Series (opaque id only) -> Season -> Block -> Episode.
--
-- `Seasons` carry no Postgres table (the `Series` aggregate is a future, additive
-- change; only the opaque `series_id` reference exists today). Each child
-- projection carries a denormalized `series_id` so the series-global
-- `(series_id, number)` numbering uniqueness can be enforced by a Postgres
-- unique index directly (ADR: production-hierarchy decision 2 & 3).

CREATE TABLE IF NOT EXISTS projection_season (
    id UUID PRIMARY KEY,
    series_id UUID NOT NULL,
    number INTEGER NOT NULL,
    title TEXT,
    version BIGINT NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_projection_season_series_number
    ON projection_season(series_id, number);
CREATE INDEX IF NOT EXISTS idx_projection_season_series_id
    ON projection_season(series_id);

CREATE TABLE IF NOT EXISTS projection_block (
    id UUID PRIMARY KEY,
    season_id UUID NOT NULL,
    series_id UUID NOT NULL,
    number INTEGER NOT NULL,
    start_date DATE,
    end_date DATE,
    version BIGINT NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_projection_block_series_number
    ON projection_block(series_id, number);
CREATE INDEX IF NOT EXISTS idx_projection_block_season_id
    ON projection_block(season_id);
CREATE INDEX IF NOT EXISTS idx_projection_block_series_id
    ON projection_block(series_id);

CREATE TABLE IF NOT EXISTS projection_episode (
    id UUID PRIMARY KEY,
    block_id UUID NOT NULL,
    series_id UUID NOT NULL,
    number INTEGER NOT NULL,
    name TEXT,
    version BIGINT NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_projection_episode_series_number
    ON projection_episode(series_id, number);
CREATE INDEX IF NOT EXISTS idx_projection_episode_block_id
    ON projection_episode(block_id);
CREATE INDEX IF NOT EXISTS idx_projection_episode_series_id
    ON projection_episode(series_id);
