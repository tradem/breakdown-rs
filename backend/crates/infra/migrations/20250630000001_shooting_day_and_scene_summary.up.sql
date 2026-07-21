-- SPDX-License-Identifier: AGPL-3.0
-- Copyright (C) 2024-2026 Breakdown RS Contributors

-- Add a free-form prose summary column to the Scene projection.
ALTER TABLE projection_scene ADD COLUMN summary TEXT;

-- ShootingDay projection: one row per episode-scoped Drehtag.
CREATE TABLE projection_shooting_day (
    id          UUID PRIMARY KEY,
    episode_id  UUID NOT NULL,
    label       TEXT,
    order_key   TEXT NOT NULL,
    date        DATE,
    source      JSONB NOT NULL,            -- {"Manual":null} | {"AiExtracted":{...}}
    archived    BOOLEAN NOT NULL DEFAULT false,
    version     BIGINT NOT NULL,
    updated_at  TIMESTAMPTZ NOT NULL
);

-- Canonical listing within an Episode is by (episode_id, order_key ASC).
CREATE INDEX idx_projection_shooting_day_episode_id
    ON projection_shooting_day(episode_id, order_key);

-- Scene <-> ShootingDay join (many-to-many; the Scene owns the link).
CREATE TABLE projection_scene_shooting_day (
    scene_id       UUID NOT NULL REFERENCES projection_scene(id) ON DELETE CASCADE,
    shooting_day_id UUID NOT NULL REFERENCES projection_shooting_day(id) ON DELETE CASCADE,
    version        BIGINT NOT NULL,
    PRIMARY KEY (scene_id, shooting_day_id)
);

-- Reverse lookup: all scenes filming on a given ShootingDay.
CREATE INDEX idx_projection_scene_shooting_day_day
    ON projection_scene_shooting_day(shooting_day_id);
