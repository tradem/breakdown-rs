-- SPDX-License-Identifier: AGPL-3.0
-- Copyright (C) 2024-2026 Breakdown RS Contributors
-- Co-authored-by: deepseek-v4.1-flash (opencode-go)

-- Job-level Decision Model scoring outcome (issue #767).
--
-- A configured Decision Model could produce "no star ratings and no
-- explanation": a job that resolved no decision config, one whose decision
-- client could not be built, one whose scoring call failed, and one whose
-- provider answered only partially all degraded to the same user-visible
-- state. The per-row `DecisionRubric.scoring_failed` flag only explains the
-- last two, and only *after* a preview exists — nothing on the job said
-- whether the worker had a Decision Model at all.
--
-- One additive, nullable JSONB column carries the answer, written by the
-- worker in the SAME owner-fenced completion write as the extraction
-- telemetry (`record_worker_telemetry`), so it can never describe a run that
-- did not happen. Payload shape (core `DecisionTelemetry`):
--
--   {"provider": "neuralwatt", "model": "glm-5.3",
--    "outcome": "ran" | "skipped_no_config" | "client_unavailable"
--             | "scoring_failed" | "skipped_not_applicable",
--    "failed_rows": 0}
--
-- No backfill on purpose: a pre-#767 run's decision outcome cannot be
-- reconstructed after the fact, so it stays NULL and the wire renders an
-- honest `null` ("not recorded") instead of a guessed class.
ALTER TABLE ai_import.ai_import_job
    ADD COLUMN decision_telemetry JSONB;

COMMENT ON COLUMN ai_import.ai_import_job.decision_telemetry IS
    'Decision Model scoring outcome recorded at completion (issue #767): resolved provider/model, outcome class and failed row count; NULL for pre-#767 rows.';
