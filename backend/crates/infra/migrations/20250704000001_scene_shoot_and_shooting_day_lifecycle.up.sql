-- SPDX-License-Identifier: AGPL-3.0
-- Copyright (C) 2024-2026 Breakdown RS Contributors
-- Co-authored-by: deepseek-v4-flash (opencode-go)

-- Add projection tables and columns for the SceneShoot aggregate,
-- ShootingDay lifecycle (wrap), and photo bindings (change:
-- add-shoot-day-execution-and-continuity).

-- ─── 5.1: projection_scene_shoot ────────────────────────────────────────────
--
-- Replaces the thin `projection_scene_shooting_day` join with a full
-- association aggregate carrying planned and actual execution data.

CREATE TABLE IF NOT EXISTS projection_scene_shoot (
    id                  UUID PRIMARY KEY,
    scene_id            UUID NOT NULL REFERENCES projection_scene(id) ON DELETE CASCADE,
    shooting_day_id     UUID NOT NULL REFERENCES projection_shooting_day(id) ON DELETE CASCADE,
    planned_order       TEXT NOT NULL,
    actual_order        TEXT,                                   -- NULL until execution data recorded
    start_dt            TIMESTAMPTZ,                            -- NULL until shoot starts
    end_dt              TIMESTAMPTZ,                            -- NULL until shoot finishes
    status              TEXT NOT NULL DEFAULT 'Planned',         -- Planned | Scheduled | InProgress | Shot | Skipped
    notes               JSONB NOT NULL DEFAULT '[]'::jsonb,      -- [{id, body}]
    continuity_photo_ids UUID[] NOT NULL DEFAULT '{}',
    version             BIGINT NOT NULL DEFAULT 1,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    -- Pair-uniqueness: one row per (scene, shooting_day)
    CONSTRAINT uq_projection_scene_shoot_pair UNIQUE (scene_id, shooting_day_id)
);

-- Dispo listing: ordered by planned_order (Soll).
CREATE INDEX IF NOT EXISTS idx_projection_scene_shoot_planned
    ON projection_scene_shoot(shooting_day_id, planned_order);

-- Shoot-day listing: ordered by actual_order (Ist), NULLs last.
CREATE INDEX IF NOT EXISTS idx_projection_scene_shoot_actual
    ON projection_scene_shoot(shooting_day_id, actual_order ASC NULLS LAST);

-- Per-scene lookup (all days a scene was shot on).
CREATE INDEX IF NOT EXISTS idx_projection_scene_shoot_scene
    ON projection_scene_shoot(scene_id);


-- ─── 5.2: projection_continuity_photo ───────────────────────────────────────
--
-- Refcount table for continuity photos. Mirrors `projection_costume_photo`
-- for the costume side; the deletion saga branches on binding kind.

CREATE TABLE IF NOT EXISTS projection_continuity_photo (
    photo_id        UUID NOT NULL REFERENCES projection_photo(photo_id) ON DELETE CASCADE,
    scene_shoot_id  UUID NOT NULL REFERENCES projection_scene_shoot(id) ON DELETE CASCADE,
    costume_id      UUID,                                       -- NULL for prop-only continuity shots
    PRIMARY KEY (photo_id, scene_shoot_id)
);

CREATE INDEX IF NOT EXISTS idx_projection_continuity_photo_shoot
    ON projection_continuity_photo(scene_shoot_id);


-- ─── 5.3: wrapped_at on projection_shooting_day ─────────────────────────────

ALTER TABLE projection_shooting_day
    ADD COLUMN IF NOT EXISTS wrapped_at TIMESTAMPTZ;            -- NULL until the day is wrapped


-- ─── 5.4: script_day on projection_scene ────────────────────────────────────

ALTER TABLE projection_scene
    ADD COLUMN IF NOT EXISTS script_day TEXT;                   -- free-form script chronology index


-- ─── 5.5: Backfill hint (one-shot, run after deployment) ────────────────────
--
-- Backfill existing `projection_scene_shooting_day` rows into
-- `projection_scene_shoot` with status 'Planned' and a seeded order:
--
--   INSERT INTO projection_scene_shoot (id, scene_id, shooting_day_id,
--       planned_order, status, version, updated_at)
--   SELECT gen_random_uuid(), psd.scene_id, psd.shooting_day_id,
--          LPAD(ROW_NUMBER() OVER (PARTITION BY psd.shooting_day_id
--              ORDER BY ps.scene_number NULLS LAST, psd.scene_id)::text, 10, '0'),
--          'Planned', 1, now()
--   FROM projection_scene_shooting_day psd
--   JOIN projection_scene ps ON ps.id = psd.scene_id
--   ON CONFLICT (scene_id, shooting_day_id) DO NOTHING;
--
-- Run this manually once after the migration applies.


-- ─── 5.6: Tag existing photos as Costume binding ────────────────────────────
--
-- The `projection_photo` table has no `binding` column; binding is an
-- event-level concept. The photo projector defaults missing `binding` to
-- `Costume` on read (backward-compat serde default). No schema change
-- is needed for historical data.
--
-- If a materialised binding column is desired later, run:
--
--   ALTER TABLE projection_photo ADD COLUMN binding JSONB NOT NULL DEFAULT '{"Costume":{"costume_id":"00000000-0000-0000-0000-000000000000"}}'::jsonb;
--
-- For now the projector handles it via the event's `serde(default)`.
