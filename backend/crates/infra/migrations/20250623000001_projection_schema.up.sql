-- SPDX-License-Identifier: AGPL-3.0
-- Copyright (C) 2024-2026 Breakdown RS Contributors

-- v1 projection schema for CQRS read models (ADR-002 + ADR-015).
-- Supersedes the temporary smoke-check migration.

DROP TABLE IF EXISTS integration_test_smoke_check;

CREATE TABLE IF NOT EXISTS projection_scene (
    id UUID PRIMARY KEY,
    project_id UUID NOT NULL,
    scene_number INTEGER,
    location TEXT,
    mood TEXT,
    is_schedule_set BOOLEAN NOT NULL DEFAULT false,
    version BIGINT NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_projection_scene_project_id ON projection_scene(project_id);

CREATE TABLE IF NOT EXISTS projection_scene_character (
    scene_id UUID NOT NULL REFERENCES projection_scene(id) ON DELETE CASCADE,
    character_id UUID NOT NULL,
    version BIGINT NOT NULL,
    PRIMARY KEY (scene_id, character_id)
);

CREATE INDEX IF NOT EXISTS idx_projection_scene_character_character_id ON projection_scene_character(character_id);

CREATE TABLE IF NOT EXISTS projection_character (
    id UUID PRIMARY KEY,
    project_id UUID NOT NULL,
    name TEXT NOT NULL,
    is_extra BOOLEAN NOT NULL,
    is_main_character BOOLEAN NOT NULL,
    measurements JSONB NOT NULL DEFAULT '{}',
    contact JSONB NOT NULL DEFAULT '{}',
    version BIGINT NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_projection_character_project_id ON projection_character(project_id);

CREATE TABLE IF NOT EXISTS projection_costume (
    id UUID PRIMARY KEY,
    project_id UUID NOT NULL,
    character_id UUID REFERENCES projection_character(id) ON DELETE SET NULL,
    notes TEXT NOT NULL DEFAULT '',
    version BIGINT NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_projection_costume_project_id ON projection_costume(project_id);
CREATE INDEX IF NOT EXISTS idx_projection_costume_character_id ON projection_costume(character_id);

CREATE TABLE IF NOT EXISTS projection_costume_detail (
    costume_id UUID NOT NULL REFERENCES projection_costume(id) ON DELETE CASCADE,
    detail_id UUID NOT NULL,
    text TEXT NOT NULL,
    PRIMARY KEY (costume_id, detail_id)
);

CREATE TABLE IF NOT EXISTS projection_costume_photo (
    costume_id UUID NOT NULL REFERENCES projection_costume(id) ON DELETE CASCADE,
    photo_id UUID NOT NULL,
    PRIMARY KEY (costume_id, photo_id)
);

CREATE TABLE IF NOT EXISTS projection_calculation (
    id UUID PRIMARY KEY,
    project_id UUID NOT NULL,
    header JSONB NOT NULL DEFAULT '{}',
    version BIGINT NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_projection_calculation_project_id ON projection_calculation(project_id);

CREATE TABLE IF NOT EXISTS projection_calculation_item (
    calculation_id UUID NOT NULL REFERENCES projection_calculation(id) ON DELETE CASCADE,
    item_id UUID NOT NULL,
    name TEXT NOT NULL,
    quantity NUMERIC NOT NULL,
    unit_price NUMERIC NOT NULL,
    is_paid BOOLEAN NOT NULL,
    PRIMARY KEY (calculation_id, item_id)
);

-- Per-projection checkpoint table consumed by kameo_es PostgresProcessor.
CREATE TABLE IF NOT EXISTS sierradb_event_checkpoints (
    projection_id TEXT NOT NULL,
    partition_id SMALLINT NOT NULL,
    last_sequence BIGINT NOT NULL,
    PRIMARY KEY (projection_id, partition_id)
);
