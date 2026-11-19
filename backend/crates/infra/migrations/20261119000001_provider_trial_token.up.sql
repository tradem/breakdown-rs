-- SPDX-License-Identifier: AGPL-3.0
-- Copyright (C) 2024-2026 Breakdown RS Contributors
-- Co-authored-by: deepseek-v4.1-flash (opencode-go)

-- The single half-open trial token (issue #942 W1).
--
-- `half_open` used to mean two things at once, and the probe closed straight
-- from it, so a metadata `200` released the whole fleet into another round of
-- doomed (and possibly still billed) paid calls — issue #942 F2 measured
-- `flap_count = 3` in 30 minutes while `GET /key` answered `200` in 0.2 s and
-- the same model's `POST /chat/completions` stalled at 120 s.
--
-- The state now has two phases: the probe (lease held, `trial_job_id` NULL) and
-- the trial (lease released, exactly one job named here). The claim predicate is
-- the only authority on WHICH job may run, because only SQL can compare the
-- token against the candidate row; closing happens only on a real paid call.
--
-- NULL is also the normal resting value: every closed/open transition clears it.
ALTER TABLE ai_import.provider_health
    ADD COLUMN trial_job_id UUID;

COMMENT ON COLUMN ai_import.provider_health.trial_job_id IS
    'The one job allowed to run the half-open trial call (issue #942 W1); NULL unless state = half_open after a passing preflight.';

-- The claim predicate looks a candidate job up against this token on every
-- claim of a non-closed pair, so the pair is indexed with its holder.
CREATE INDEX idx_provider_health_trial_job
    ON ai_import.provider_health (trial_job_id)
    WHERE trial_job_id IS NOT NULL;
