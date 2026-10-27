-- SPDX-License-Identifier: AGPL-3.0
-- Copyright (C) 2024-2026 Breakdown RS Contributors
-- Co-authored-by: deepseek-v4.1-flash (opencode-go)

-- Restore the pre-split costume projections (schema only — event data is not
-- migrated in either direction; dev volumes are reset instead).
DROP TABLE IF EXISTS projection_scene_outfit_assignment;
DROP TABLE IF EXISTS projection_outfit_photo;
DROP TABLE IF EXISTS projection_outfit_piece;
DROP TABLE IF EXISTS projection_outfit;
DROP TABLE IF EXISTS projection_piece_photo;
DROP TABLE IF EXISTS projection_piece_detail;
DROP TABLE IF EXISTS projection_piece_season;
DROP TABLE IF EXISTS projection_piece;

CREATE TABLE projection_costume (
    id                UUID PRIMARY KEY,
    character_id      UUID,
    category_id       UUID,
    category_name     TEXT,
    notes             TEXT NOT NULL DEFAULT '',
    version           BIGINT NOT NULL,
    projector_version BIGINT NOT NULL DEFAULT 0,
    updated_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_projection_costume_character_id
    ON projection_costume(character_id);

CREATE TABLE projection_costume_season (
    costume_id UUID NOT NULL REFERENCES projection_costume(id) ON DELETE CASCADE,
    season_id  UUID NOT NULL,
    PRIMARY KEY (costume_id, season_id)
);

-- Column set as of the pre-split schema: `20250701000001` added the legacy
-- category columns and `20260806000001` the projector marker, so both must be
-- present for those migrations to roll back cleanly.
CREATE TABLE projection_costume_detail (
    costume_id        UUID NOT NULL REFERENCES projection_costume(id) ON DELETE CASCADE,
    detail_id         UUID NOT NULL,
    subject           TEXT,
    text              TEXT NOT NULL,
    category_id       UUID,
    category_name     TEXT,
    projector_version BIGINT NOT NULL DEFAULT 0,
    PRIMARY KEY (costume_id, detail_id)
);

CREATE TABLE projection_costume_photo (
    costume_id        UUID NOT NULL REFERENCES projection_costume(id) ON DELETE CASCADE,
    photo_id          UUID NOT NULL,
    projector_version BIGINT NOT NULL DEFAULT 0,
    PRIMARY KEY (costume_id, photo_id)
);

CREATE TABLE projection_scene_costume_assignment (
    scene_id     UUID NOT NULL REFERENCES projection_scene(id) ON DELETE CASCADE,
    character_id UUID NOT NULL,
    "order"      INTEGER NOT NULL,
    costume_id   UUID NOT NULL,
    note         TEXT,
    version      BIGINT NOT NULL,
    PRIMARY KEY (scene_id, character_id, "order")
);

CREATE INDEX idx_projection_scene_costume_assignment_costume
    ON projection_scene_costume_assignment(costume_id);

UPDATE projection_photo SET binding = 'Costume' WHERE binding = 'Piece';

ALTER TABLE projection_continuity_photo RENAME COLUMN piece_id TO costume_id;
