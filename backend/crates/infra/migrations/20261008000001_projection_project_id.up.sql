-- SPDX-License-Identifier: AGPL-3.0
-- Copyright (C) 2024-2026 Breakdown RS Contributors
-- Co-authored-by: space-bunny (opencode-go)

-- Layer 3 of the `SeriesId` → `ProjectId` rename (issue #599, ADR-035 S1/B4/B5,
-- completing the projection-column layer left open by issue #591).
--
-- Only *spelling* changes here: the tenant container id keeps the same UUIDv7
-- values, the same tenant boundary (ADR-035 B1) and the same audit-journal
-- scope (B3). No row is touched, no constraint is relaxed.
--
-- ADR-021 D6 reading (documented deviation, deliberately): D6 forbids renaming
-- a column "consumed by an open API version" during a deprecation window. This
-- migration lands in a pre-production release: `/v1` is still the only served
-- path version, and no first-party client has ever been released against it,
-- so no deprecation window is open and no client reads the column by name.
-- `/v1` and `/v2` would be served by the *same* binary anyway, so the read
-- model is not a cross-version external contract — the queries that consume
-- these columns are updated in the same change. Renaming now is therefore
-- strictly cheaper than deferring: a deferral would leave the storage spelling
-- and the wire spelling permanently out of step for the life of the project.

-- Season numbering uniqueness: (series_id, number) → (project_id, number)
-- (ADR-035 B4 — the uniqueness key is prefixed with the tenant id, not with a
-- production-form-specific one).
ALTER INDEX IF EXISTS idx_projection_season_series_number
    RENAME TO idx_projection_season_project_number;
ALTER TABLE projection_season
    RENAME COLUMN series_id TO project_id;
ALTER INDEX IF EXISTS idx_projection_season_series_id
    RENAME TO idx_projection_season_project_id;

-- Block numbering uniqueness.
ALTER INDEX IF EXISTS idx_projection_block_series_number
    RENAME TO idx_projection_block_project_number;
ALTER TABLE projection_block
    RENAME COLUMN series_id TO project_id;
ALTER INDEX IF EXISTS idx_projection_block_series_id
    RENAME TO idx_projection_block_project_id;

-- Episode numbering uniqueness.
ALTER INDEX IF EXISTS idx_projection_episode_series_number
    RENAME TO idx_projection_episode_project_number;
ALTER TABLE projection_episode
    RENAME COLUMN series_id TO project_id;
ALTER INDEX IF EXISTS idx_projection_episode_series_id
    RENAME TO idx_projection_episode_project_id;

-- The audit journal's tenant dimension (ADR-035 B3 — the scope is unchanged,
-- only the column name follows the type rename).
ALTER INDEX IF EXISTS idx_projection_audit_series
    RENAME TO idx_projection_audit_project;
ALTER TABLE projection_audit
    RENAME COLUMN series_id TO project_id;

-- ADR-036 reservation-stream key prefixes are **value-derived** and must not
-- change: the synthetic stream keys are `seasnum-{uuid_simple(project_id)}-{n}`,
-- `blocknum-…` and `epnum-…` (crates/infra/src/reservations/event.rs). They
-- carry no literal column name, so renaming the column cannot orphan a live
-- reservation claim. `projection_number_reservation` stores the fully-formed
-- key string and is therefore untouched by this migration as well.