-- SPDX-License-Identifier: AGPL-3.0
-- Copyright (C) 2024-2026 Breakdown RS Contributors

-- Reverse of 20261107000001: drop the Decision-Model score columns. The
-- event payloads keep their (serde-defaulted) fields; a re-apply of the
-- projector after the down migration would simply have nothing to write.
ALTER TABLE projection_scene
    DROP COLUMN IF EXISTS scene_score,
    DROP COLUMN IF EXISTS synopsis_score;
