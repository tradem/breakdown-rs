-- SPDX-License-Identifier: AGPL-3.0
-- Copyright (C) 2024-2026 Breakdown RS Contributors

-- Undo the `projection_scene.source` provenance column (issue #517).
ALTER TABLE projection_scene
    DROP COLUMN IF EXISTS source;
