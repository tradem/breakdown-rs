-- SPDX-License-Identifier: AGPL-3.0
-- Copyright (C) 2024-2026 Breakdown RS Contributors
-- Co-authored-by: glm-5.3-flash (opencode-go)

-- Season lifecycle (issue #533): the terminal `archived` flag on the season
-- projection. Existing rows retroactively read `false` (never archived), new
-- rows default to `false` — the projector writes the flag explicitly on every
-- upsert, so no backfill is needed.
--
-- The (series_id, number) unique index `idx_projection_season_series_number`
-- stays untouched by design: an archived season still blocks reuse of its
-- number (the number is historical identity; re-issuing it would entangle old
-- audit/report references — decision recorded in issue #533).

ALTER TABLE projection_season
    ADD COLUMN archived BOOLEAN NOT NULL DEFAULT false;
