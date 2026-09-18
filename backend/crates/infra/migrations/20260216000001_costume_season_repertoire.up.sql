-- SPDX-License-Identifier: AGPL-3.0
-- Copyright (C) 2024-2026 Breakdown RS Contributors

-- Season repertoire join table for costumes (issue #453).
--
-- The season costume stream previously scoped exclusively through the
-- character join (`projection_costume.character_id → projection_character
-- .season_id`), so an unassigned costume (`character_id IS NULL`) never
-- appeared in ANY season's stream — there was no UI path to a first
-- assignment. The repertoire join breaks that artificial coupling: a costume
-- can be *in repertoire* for one or more seasons (main characters reuse
-- costumes across seasons), and the stream lists the union of
-- assigned-to-season-character OR in-season-repertoire.
--
-- Write path: `CostumeCreated` carries `season_id` (serde(default) — old
-- events replay as NULL) and the costume projector inserts the row.
-- Pre-production: the table starts empty; a projection rebuild replays
-- old events with repertoire NULL, which is contract-compatible.

CREATE TABLE IF NOT EXISTS projection_costume_season (
    costume_id UUID NOT NULL REFERENCES projection_costume(id) ON DELETE CASCADE,
    season_id  UUID NOT NULL,
    PRIMARY KEY (costume_id, season_id)
);

CREATE INDEX IF NOT EXISTS idx_projection_costume_season_season_id
    ON projection_costume_season(season_id);
