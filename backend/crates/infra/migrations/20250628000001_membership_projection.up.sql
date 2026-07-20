-- SPDX-License-Identifier: AGPL-3.0
-- Copyright (C) 2024-2026 Breakdown RS Contributors

-- Block-scoped membership projection (CQRS read model for the `membership`
-- Bounded Context). One row per (block_id, user_id). `user_id` is the opaque
-- OIDC `sub` string; `role`/`state` are stored as their serde JSON string form
-- (e.g. "Kostümbildner" / "pending") so they round-trip through the domain enum.

CREATE TABLE IF NOT EXISTS projection_membership (
    block_id UUID NOT NULL,
    user_id TEXT NOT NULL,
    role TEXT NOT NULL,
    state TEXT NOT NULL,
    joined_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (block_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_projection_membership_block_id ON projection_membership(block_id);
