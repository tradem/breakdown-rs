-- SPDX-License-Identifier: AGPL-3.0
-- Copyright (C) 2024-2026 Breakdown RS Contributors
-- Co-authored-by: deepseek-v4.1-flash (opencode-go)

-- Chunk-level resume (issue #871, workstream B; design D-B1/B2/B3/B7).
--
-- A retried attempt used to restart at chunk 0, so a 42-chunk document that died
-- at chunk 25 paid for the same ~25 chunks three times. The stored unit is the
-- parsed chunk RESULT — exactly what one paid call returned — because that is
-- what makes the resume unit equal the paid call.
--
-- A table, not a JSONB column on the job row, for three concrete reasons:
--
--   * write amplification: one write per chunk against a growing document is
--     O(n²) bytes for a 128-chunk script, while a chunk row is a bounded insert;
--   * `ai_import_job.updated_at` is LOAD-BEARING — it is the retention clock, the
--     payload-GC `ORDER BY` key and the ETA anchor `started_at` (#762), and the
--     AI-import instructions forbid a sweep from touching it. Writing it once per
--     chunk would re-arm all three;
--   * observability: "how many chunks are done" becomes `count(*)`, which is what
--     makes resume auditable in SQL instead of by reading a blob.
CREATE TABLE ai_import.ai_import_job_chunk (
    job_id      UUID        NOT NULL
                REFERENCES ai_import.ai_import_job(id) ON DELETE CASCADE,
    chunk_index INTEGER     NOT NULL CHECK (chunk_index >= 0),
    -- The per-chunk `ScriptContext`-shaped parse result (D-B3).
    payload     JSONB       NOT NULL,
    -- The usage that chunk's call(s) consumed, so the completion cost snapshot
    -- counts every paid call exactly once across attempts (D-B4).
    usage       JSONB       NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    -- The primary key IS the idempotency mechanism: a chunk re-run after a lost
    -- write repairs itself with `ON CONFLICT … DO UPDATE`, so resume needs no
    -- per-row reservation machinery.
    PRIMARY KEY (job_id, chunk_index)
);

COMMENT ON TABLE ai_import.ai_import_job_chunk IS
    'Parsed per-chunk extraction results (issue #871). The resume cursor is the contiguous prefix length, derived — never stored.';

-- The extraction fingerprint (D-B7): `sha256(document_digest | provider | model |
-- sha256(effective prompt) | chunker_version)`. A changed key means the stored
-- chunks were produced by a different configuration and must not be resumed
-- across, so the invalidation path deletes them and restarts at 0.
ALTER TABLE ai_import.ai_import_job
    ADD COLUMN extraction_key TEXT;

-- The fingerprint's COMPONENTS, stored next to its hash. D-B7 asks the operator
-- to know *what* changed (model, prompt or chunker) to judge whether a restart
-- was necessary; a hash alone cannot answer that, and there is no prompt version
-- anywhere in the system to compare against.
ALTER TABLE ai_import.ai_import_job
    ADD COLUMN extraction_key_components JSONB;

COMMENT ON COLUMN ai_import.ai_import_job.extraction_key IS
    'Extraction fingerprint of the stored chunk set (issue #871 D-B7). Written compare-and-set at the first stored chunk of an attempt; a mismatch invalidates the whole set.';
COMMENT ON COLUMN ai_import.ai_import_job.extraction_key_components IS
    'The fingerprint inputs (document digest, provider, model, prompt hash, chunker version), so an invalidation can name what changed instead of only that something did.';
