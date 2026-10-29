-- SPDX-License-Identifier: AGPL-3.0
-- Copyright (C) 2024-2026 Breakdown RS Contributors
-- Co-authored-by: deepseek-v4.1-flash (opencode-go)

-- Script scene reconciliation counters for AI import jobs (issue #758).
--
-- Three additive, `NOT NULL DEFAULT 0` columns so the pipeline can state how
-- many scene headings the *document* had, how many preview rows the *model*
-- produced, and how many rows had to be rebuilt from the deterministic heading
-- because their chunk returned nothing. Before this, the only observable
-- number was the model's row count, so a 57-heading script that produced a
-- 4-row preview looked like a successful import of 4 scenes.
--
-- * `scenes_detected`  — scene headings detected by the deterministic scan
--   (the chunk count after duplicate-heading merging).
-- * `scenes_extracted` — preview rows the extraction model returned, summed
--   over all chunks. Deliberately EXCLUDES synthesized rows, so
--   `scenes_detected > scenes_extracted` remains the visible shortfall.
-- * `scenes_synthesized` — rows rebuilt from the document heading after their
--   chunk produced no rows at all; `0` on a healthy run.
--
-- All three stay `0` for schedule jobs (no scene headings), for jobs recorded
-- before this migration, and for runs that never reached the storing boundary.
ALTER TABLE ai_import.ai_import_job
    ADD COLUMN scenes_detected INT NOT NULL DEFAULT 0,
    ADD COLUMN scenes_extracted INT NOT NULL DEFAULT 0,
    ADD COLUMN scenes_synthesized INT NOT NULL DEFAULT 0;

ALTER TABLE ai_import.ai_import_job
    ADD CONSTRAINT ai_import_job_scenes_nonnegative CHECK (
        scenes_detected >= 0 AND scenes_extracted >= 0 AND scenes_synthesized >= 0
    );

COMMENT ON COLUMN ai_import.ai_import_job.scenes_detected IS
    'Scene headings the deterministic scan detected for a script job (issue #758); 0 for schedule jobs and pre-#758 rows.';

COMMENT ON COLUMN ai_import.ai_import_job.scenes_extracted IS
    'Preview rows the extraction model returned for a script job (issue #758), excluding rows rebuilt from document metadata.';

COMMENT ON COLUMN ai_import.ai_import_job.scenes_synthesized IS
    'Preview rows rebuilt from the deterministic heading because their chunk produced no rows (issue #758); 0 on a healthy run.';
