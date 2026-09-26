-- Undo the `projection_scene.source` provenance column (issue #517).
ALTER TABLE projection_scene
    DROP COLUMN IF EXISTS source;
