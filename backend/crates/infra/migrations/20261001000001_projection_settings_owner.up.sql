-- SPDX-License-Identifier: AGPL-3.0
-- Copyright (C) 2024-2026 Breakdown RS Contributors
-- Co-authored-by: glm-5.3 (neuralwatt)

-- Owner column for the reference-only settings projection (issue #552).
--
-- Carries the identity of the user who bound the credential, recovered by
-- the projector from `EventMetadata.actor` (persisted with every settings
-- event since ADR-027). The AI-config API edge compares this owner against
-- the authorized caller so a client cannot reference another user's live
-- credential binding (confused deputy).
--
-- Nullable on purpose: rows projected before this migration carry NULL
-- until (a) a re-projection replays the actor metadata, or (b) the owner
-- rotates the key (the rotate arm COALESCE-backfills). The API edge treats
-- NULL as "not owned by the caller" — fail closed (issue #552 decision).
ALTER TABLE projection_settings ADD COLUMN owner TEXT;

CREATE INDEX idx_projection_settings_owner
    ON projection_settings (owner);
