-- SPDX-License-Identifier: AGPL-3.0
-- Copyright (C) 2024-2026 Breakdown RS Contributors
-- Co-authored-by: glm-5.3-flash-flex (neuralwatt)

-- Live extraction progress for AI import jobs (issue #664).
--
-- The operational queue row gains a nullable `progress` JSONB column so a
-- running job can surface *where* it is (extraction stage, per-chunk
-- position, discovered episode labels) instead of only a coarse status.
-- NULL for jobs that have not published progress yet: fresh `pending`
-- claims and freshly re-claimed retry attempts (the claim SQL resets the
-- column, so stale progress from a prior attempt is never served).
--
-- Owner-fenced, throttled writes only (`mark_progress`, ADR-038 D3): stage
-- boundaries and completed chunks, never per LLM token. Advisory visibility
-- data — never correctness state, never a source of business truth.
ALTER TABLE ai_import.ai_import_job
    ADD COLUMN progress JSONB;

COMMENT ON COLUMN ai_import.ai_import_job.progress IS
    'Live extraction progress (stage, chunk, chunks_total, episodes_seen); NULL until a worker publishes it, reset on retry reclaim.';
