-- SPDX-License-Identifier: AGPL-3.0
-- Copyright (C) 2024-2026 Breakdown RS Contributors

-- Drop orphaned projection tables for the removed `calculation` context.
--
-- Per ADR / AGENTS.md: "The `calculation` context was removed; do not
-- reintroduce it."  The source code was already deleted, but the initial
-- projection migration (20250623000001) still creates these tables.  No
-- projector writes to them, no repository reads them, no handler queries
-- them.
--
-- See GitHub issue #118 for the full orphan-verification audit.

DROP TABLE IF EXISTS projection_calculation_item;
DROP TABLE IF EXISTS projection_calculation;
