-- SPDX-License-Identifier: AGPL-3.0
-- Copyright (C) 2024-2026 Breakdown RS Contributors
-- Co-authored-by: glm-5.3-flash (opencode-go)

-- Ordered costume beats per (scene, character) — the scene-side casting
-- relation (issue #546). "A character in this scene wears these costumes, in
-- this order" becomes a structural property of the projection: the primary
-- key rules out two costumes at one position and duplicate positions.
-- Denseness of `order` is an aggregate fact (computed as max + 1 on add);
-- the projector never renumbers.
--
-- `order` is quoted: it is a reserved-ish word risk in some Postgres
-- versions and kept lowercase for consistency with the Rust field.
--
-- No cascade to `projection_costume`: a costume is never deleted (mirrors
-- `projection_costume_photo`).
CREATE TABLE projection_scene_costume_assignment (
    scene_id     UUID NOT NULL REFERENCES projection_scene(id) ON DELETE CASCADE,
    character_id UUID NOT NULL,
    "order"      INTEGER NOT NULL,
    costume_id   UUID NOT NULL,
    note         TEXT,
    version      BIGINT NOT NULL,
    PRIMARY KEY (scene_id, character_id, "order")
);

-- Reverse lookup: in which scenes is this costume worn?
CREATE INDEX idx_projection_scene_costume_assignment_costume
    ON projection_scene_costume_assignment(costume_id);
