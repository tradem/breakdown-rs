-- SPDX-License-Identifier: AGPL-3.0
-- Copyright (C) 2024-2026 Breakdown RS Contributors

DROP TABLE IF EXISTS sierradb_event_checkpoints;
DROP TABLE IF EXISTS projection_calculation_item;
DROP TABLE IF EXISTS projection_calculation;
DROP TABLE IF EXISTS projection_costume_photo;
DROP TABLE IF EXISTS projection_costume_detail;
DROP TABLE IF EXISTS projection_costume;
DROP TABLE IF EXISTS projection_character;
DROP TABLE IF EXISTS projection_scene_character;
DROP TABLE IF EXISTS projection_scene;

-- Recreate the temporary smoke-check table for backwards compatibility of old tests.
CREATE TABLE IF NOT EXISTS integration_test_smoke_check (
    id UUID PRIMARY KEY,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
