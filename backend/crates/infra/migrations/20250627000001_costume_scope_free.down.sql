-- SPDX-License-Identifier: AGPL-3.0
-- Copyright (C) 2024-2026 Breakdown RS Contributors

ALTER TABLE projection_costume ADD COLUMN project_id UUID NOT NULL DEFAULT '00000000-0000-0000-0000-000000000000';
