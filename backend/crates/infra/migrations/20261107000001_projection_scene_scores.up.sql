-- SPDX-License-Identifier: AGPL-3.0
-- Copyright (C) 2024-2026 Breakdown RS Contributors

-- Decision-Model quality scores on the scene projection (issue #834).
-- `SceneDetails` carries `scene_score` / `synopsis_score` (issue #722's
-- `DraftScene` fields) from the AI apply onward; the projector writes them
-- on `SceneCreated` and PRESERVES them on `SceneDetailsUpdated` (a later
-- detail edit must not erase the recorded provenance — re-scoring is out of
-- scope for #834). Nullable `double precision`: a manual scene has no score
-- and a failed best-effort scoring pass records no value (honest absence,
-- never a fabricated one). Existing rows predate scoring and stay `NULL`.
ALTER TABLE projection_scene
    ADD COLUMN IF NOT EXISTS scene_score DOUBLE PRECISION,
    ADD COLUMN IF NOT EXISTS synopsis_score DOUBLE PRECISION;
