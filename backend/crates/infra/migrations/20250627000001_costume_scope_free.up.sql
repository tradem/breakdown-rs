-- SPDX-License-Identifier: AGPL-3.0
-- Copyright (C) 2024-2026 Breakdown RS Contributors

-- Make the Costume projection scope-free: drop the `project_id` column.
-- A Costume has no independent scope — it is resolved via `character_id`
-- (Character -> Season -> Series) when needed. Pre-production: the table is
-- empty, so the drop is safe.

ALTER TABLE projection_costume DROP COLUMN project_id;
