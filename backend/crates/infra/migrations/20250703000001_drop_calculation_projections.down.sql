-- SPDX-License-Identifier: AGPL-3.0
-- Copyright (C) 2024-2026 Breakdown RS Contributors

-- Recreate the orphaned projection tables exactly as they were in
-- 20250623000001_projection_schema.up.sql, so the migration-reversibility
-- test (smoke_postgres_harness.rs) can successfully undo this migration.

CREATE TABLE IF NOT EXISTS projection_calculation (
    id UUID PRIMARY KEY,
    project_id UUID NOT NULL,
    header JSONB NOT NULL DEFAULT '{}',
    version BIGINT NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_projection_calculation_project_id ON projection_calculation(project_id);

CREATE TABLE IF NOT EXISTS projection_calculation_item (
    calculation_id UUID NOT NULL REFERENCES projection_calculation(id) ON DELETE CASCADE,
    item_id UUID NOT NULL,
    name TEXT NOT NULL,
    quantity NUMERIC NOT NULL,
    unit_price NUMERIC NOT NULL,
    is_paid BOOLEAN NOT NULL,
    PRIMARY KEY (calculation_id, item_id)
);
