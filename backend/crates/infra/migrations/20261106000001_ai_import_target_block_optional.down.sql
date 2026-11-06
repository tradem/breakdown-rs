-- SPDX-License-Identifier: AGPL-3.0
-- Copyright (C) 2024-2026 Breakdown RS Contributors
-- Co-authored-by: deepseek-v4.1-flash (opencode-go)

-- Restore the pre-#829 column documentation. The column itself is untouched
-- (the migration is comment-only), so no data can be lost in either direction.
COMMENT ON COLUMN ai_import.ai_import_job.target_block_number IS
    'Production-global number of the target block at dispatch time (issue #771); NULL when unresolved.';
