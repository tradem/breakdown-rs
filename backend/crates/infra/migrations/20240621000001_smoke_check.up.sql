-- SPDX-License-Identifier: AGPL-3.0
-- Copyright (C) 2024 Breakdown RS Contributors

CREATE TABLE IF NOT EXISTS integration_test_smoke_check (
    id UUID PRIMARY KEY,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
