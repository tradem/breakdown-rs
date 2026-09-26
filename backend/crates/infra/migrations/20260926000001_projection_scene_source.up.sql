-- SPDX-License-Identifier: AGPL-3.0
-- Copyright (C) 2024-2026 Breakdown RS Contributors

-- Projection column for AI provenance on scenes (issue #517, EU AI Act
-- Art. 50 transparency): `SceneSource` as structured JSONB, mirroring
-- `projection_shooting_day.source`. Existing rows are user-created scenes and
-- get the `Manual` default; the projector writes the event's discriminator on
-- insert/redelivery.
ALTER TABLE projection_scene
    ADD COLUMN IF NOT EXISTS source JSONB NOT NULL DEFAULT '{"Manual":null}'::jsonb;
