-- SPDX-License-Identifier: AGPL-3.0
-- Copyright (C) 2024-2026 Breakdown RS Contributors
-- Co-authored-by: glm-5.3 (neuralwatt)

-- Per-attempt failure history for AI import jobs (issue #637).
--
-- `ai_import_job.last_error` is overwritten by every `mark_failed`, so the
-- reason an *earlier* attempt failed is lost — the observability gap that made
-- the expired-Vault-token incident hard to explain. One row is appended per
-- failed attempt (and per payload-unavailable discovery), so every attempt's
-- outcome stays retrievable. Operational data, never a source of business
-- truth; the ON DELETE CASCADE keeps it from outliving its job.
CREATE TABLE ai_import.ai_import_job_attempt (
    id            UUID PRIMARY KEY,
    job_id        UUID NOT NULL
                  REFERENCES ai_import.ai_import_job (id) ON DELETE CASCADE,
    attempt_no    INT NOT NULL CHECK (attempt_no >= 1),
    status        TEXT NOT NULL
                  CHECK (status IN ('failed', 'dead_letter', 'payload_unavailable')),
    error_summary TEXT,
    retryable     BOOLEAN NOT NULL,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Newest-first history lookup per job, bounded by the read adapter.
CREATE INDEX idx_ai_import_job_attempt_job
    ON ai_import.ai_import_job_attempt (job_id, attempt_no DESC);

COMMENT ON TABLE ai_import.ai_import_job_attempt IS
    'Per-attempt AI import failure history; never a source of business truth.';
