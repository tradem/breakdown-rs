-- SPDX-License-Identifier: AGPL-3.0
-- Copyright (C) 2024-2026 Breakdown RS Contributors
-- Co-authored-by: glm-5.3 (neuralwatt)

-- Revert the outcome attribution column (review of #899). Ownership
-- (`apply_run_id`), the progress payload and the persisted result are
-- untouched — they are the #762/#800/#899 contract.
ALTER TABLE ai_import.ai_import_job
    DROP COLUMN IF EXISTS apply_result_run_id;
