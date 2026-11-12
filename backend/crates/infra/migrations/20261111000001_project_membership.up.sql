-- SPDX-License-Identifier: AGPL-3.0
-- Copyright (C) 2024-2026 Breakdown RS Contributors
-- Co-authored-by: deepseek-v4.1-flash (opencode-go)
--
-- Project-scoped costume membership (openspec/changes/project-scoped-membership).
--
-- Block membership grants a role AT A BLOCK, which is the scope that rotates at
-- block boundaries - so a production without a block yet had no roles at all and
-- every season-scoped authorization check on it was refused (a season with no
-- block could never authorize an AI-import upload). This projection carries the
-- additive project scope: one role per (project, user).
--
-- Shape mirrors projection_membership (role as TEXT, an explicit state column so
-- a revocation is a state transition rather than a row delete, and a
-- projector_version for the version-guarded upsert).

CREATE TABLE IF NOT EXISTS projection_project_membership (
    project_id        UUID        NOT NULL,
    user_id           TEXT        NOT NULL,
    role              TEXT        NOT NULL,
    state             TEXT        NOT NULL,
    joined_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    projector_version BIGINT      NOT NULL DEFAULT 0,
    PRIMARY KEY (project_id, user_id)
);

-- The authorization hot path is one lookup:
--   "does <user> hold an active costume role on <project>?"
-- which is exactly this index's prefix.
CREATE INDEX IF NOT EXISTS idx_projection_project_membership_active_role
    ON projection_project_membership (project_id, state, role)
    WHERE state = 'active';
