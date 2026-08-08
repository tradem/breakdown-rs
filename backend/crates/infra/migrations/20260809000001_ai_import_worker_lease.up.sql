-- SPDX-License-Identifier: AGPL-3.0
-- Copyright (C) 2024-2026 Breakdown RS Contributors
-- Co-authored-by: longcat-2.0-free (opencode)

-- Issue #177: worker leases for AI import jobs.
--
-- `claim_next`/`claim_next_kind` previously flipped a row to `running` without
-- recording *who* claimed it or *until when*. A worker that crashed or was
-- evicted therefore left the job in `running` forever, invisible to the claim
-- predicates. Two columns make a claim recoverable:
--   * `worker_id`         — the claiming worker (diagnostics / ownership)
--   * `lease_expires_at`  — the deadline after which the claim is void and
--                           another worker may reclaim the job atomically.
ALTER TABLE ai_import.ai_import_job
    ADD COLUMN IF NOT EXISTS worker_id        TEXT,
    ADD COLUMN IF NOT EXISTS lease_expires_at TIMESTAMPTZ;

-- Rows already stuck in `running` predate the lease contract and have no
-- owner that could still be alive after this deployment. Expiring their lease
-- immediately makes them recoverable on the next claim instead of leaking.
UPDATE ai_import.ai_import_job
SET lease_expires_at = now()
WHERE status = 'running'
  AND lease_expires_at IS NULL;

-- The claim predicate now also scans expired `running` leases; keep that path
-- indexed alongside the existing (status, next_attempt_at, created_at) index.
CREATE INDEX IF NOT EXISTS idx_ai_import_job_lease
    ON ai_import.ai_import_job (status, lease_expires_at);

COMMENT ON COLUMN ai_import.ai_import_job.worker_id IS
    'Worker that holds the current claim; NULL when the job is unclaimed or terminal.';
COMMENT ON COLUMN ai_import.ai_import_job.lease_expires_at IS
    'Claim deadline; a running job may be reclaimed once this timestamp has passed.';
