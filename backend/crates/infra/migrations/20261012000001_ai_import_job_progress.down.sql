-- SPDX-License-Identifier: AGPL-3.0
-- Copyright (C) 2024-2026 Breakdown RS Contributors
-- Co-authored-by: glm-5.3 (neuralwatt)

-- Revert issue #664: drop the advisory progress column.
ALTER TABLE ai_import.ai_import_job
    DROP COLUMN IF EXISTS progress;
