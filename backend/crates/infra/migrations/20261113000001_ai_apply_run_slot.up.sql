-- SPDX-License-Identifier: AGPL-3.0
-- Copyright (C) 2024-2026 Breakdown RS Contributors
-- Co-authored-by: glm-5.3 (neuralwatt)

-- The apply run becomes a DURABLE work item (issue #899, design D1).
--
-- Before this migration the apply had no state of its own: "a run is requested"
-- was implicit in "an HTTP request is executing it", so a client that vanished
-- (Android Doze, a Wi-Fi→cellular handover, a closed socket) dropped the
-- handler future and the run simply stopped mid-row. The only trace left was a
-- transient progress payload, and the only remedy a second POST.
--
-- Three columns fix that, all on the row that already holds the single-flight
-- claim, the progress payload and the crash-recovery stamps — no new table, no
-- join (design D1: one run slot per preview is the contract):
--
--   * `apply_state`  — the lifecycle a worker can poll
--     (`idle` | `requested` | `running` | `done` | `failed`);
--   * `apply_request` — the resolved request (reviewer decisions, target
--     episode/season/block, day groups, category vocabulary), because a worker
--     on ANOTHER replica cannot recover the reviewer's payload from the stored
--     preview, and a restart between claim and dispatch must not strand a
--     `requested` row;
--   * `apply_result`  — the persisted outcome (counters or the registered
--     problem code), so the outcome outlives the client that asked for it
--     (design D4). A re-apply overwrites it with a new run.
--
-- `idle` is the honest default for every existing row: none of them has ever
-- dispatched a durable run, and reading them as `requested` would make the
-- worker re-drive applies nobody asked for.
--
-- The partial index is what keeps the worker's poll cheap: it selects only
-- `requested` rows (the `running` recovery path additionally filters by the
-- staleness window, which is far more selective in practice than the state).
ALTER TABLE ai_import.ai_import_job
    ADD COLUMN apply_state TEXT NOT NULL DEFAULT 'idle',
    ADD COLUMN apply_request JSONB,
    ADD COLUMN apply_result JSONB;

ALTER TABLE ai_import.ai_import_job
    ADD CONSTRAINT ai_import_job_apply_state_check
    CHECK (apply_state IN ('idle', 'requested', 'running', 'done', 'failed'));

CREATE INDEX idx_ai_import_job_apply_requested
    ON ai_import.ai_import_job (apply_state, updated_at)
    WHERE apply_state IN ('requested', 'running');

COMMENT ON COLUMN ai_import.ai_import_job.apply_state IS
    'Apply-run slot lifecycle (issue #899): idle | requested | running | done | failed. A client re-enters from this field instead of re-applying.';
COMMENT ON COLUMN ai_import.ai_import_job.apply_request IS
    'The resolved apply request a worker executes (issue #899). Persisted so ANY replica can run a requested row after a rolling deploy or a crashed dispatcher.';
COMMENT ON COLUMN ai_import.ai_import_job.apply_result IS
    'Persisted outcome of the last finished apply run (issue #899): the counters, or the registered problem code of a failed run.';
