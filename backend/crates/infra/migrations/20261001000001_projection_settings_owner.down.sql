-- SPDX-License-Identifier: AGPL-3.0
-- Copyright (C) 2024-2026 Breakdown RS Contributors
-- Co-authored-by: glm-5.3 (neuralwatt)

DROP INDEX IF EXISTS idx_projection_settings_owner;

ALTER TABLE projection_settings DROP COLUMN IF EXISTS owner;
