-- SPDX-License-Identifier: AGPL-3.0
-- Copyright (C) 2024-2026 Breakdown RS Contributors
-- Co-authored-by: longcat-2.0-free (opencode)

-- Dropping the marks is safe in the direction that matters: the sweep falls
-- back to its pre-#206 behaviour of re-selecting already-cleaned jobs, whose
-- deletions are idempotent no-ops. Nothing is lost that the object store
-- cannot re-derive.
DROP TABLE IF EXISTS ai_import.ai_payload_cleanup;
