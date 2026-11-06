-- SPDX-License-Identifier: AGPL-3.0
-- Copyright (C) 2024-2026 Breakdown RS Contributors
-- Co-authored-by: deepseek-v4.1-flash (opencode-go)

-- An apply run's silence must be measured from the instant its CLAIM took the
-- slot — not from the row's `updated_at` (issue #863 review).
--
-- #863 aged an owner that never published a frame by `ai_import_job.updated_at`,
-- because that is the column the single-flight claim's steal predicate compares
-- for the unpublished state. The column is not owner-scoped though: every
-- run-scoped write bumps it, including a PREVIOUS apply's post-apply summary
-- (`record_applied_episodes`) or its telemetry, and those land after that apply
-- released the slot. A late write can therefore land after the next claim and
-- advance the stamp that describes the new owner — understating a dead run's
-- silence by exactly the gap to that write, and delaying the steal by the same
-- amount. Small, but it is the wrong column for a liveness window: the whole
-- point of #863 is that the reported age and the steal decision agree.
--
-- `apply_claim_at` is written by the claim (and by a stealing claim) and by
-- nothing else, so both the predicate and the reported age read ONE
-- owner-scoped instant.
--
-- No backfill on purpose: a claim made before this column existed keeps NULL,
-- which reports no age (honest — the instant was never recorded) while the
-- predicate falls back to the row stamp it used before (`COALESCE`), so a
-- rolling deploy never makes a live pre-migration claim stealable.
ALTER TABLE ai_import.ai_import_job
    ADD COLUMN apply_claim_at TIMESTAMPTZ;

COMMENT ON COLUMN ai_import.ai_import_job.apply_claim_at IS
    'When the current apply run took the progress slot (issue #863): stamped by the claim and by nothing else, so the steal predicate and the reported silence share one owner-scoped instant.';
