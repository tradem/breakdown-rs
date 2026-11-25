-- SPDX-License-Identifier: AGPL-3.0
-- Copyright (C) 2024-2026 Breakdown RS Contributors

-- The per-request **billed-call ledger** of an AI-import job (issue #970,
-- CodeRabbit review PR #967).
--
-- One JSONB array element per paid provider request, in billing order:
--   {"tokens_in": N, "tokens_out": N, "cached_tokens_in": N,
--    "energy_millijoules": N}
--
-- Why a separate ledger and not the completion-time counters
-- (`tokens_in`, `tokens_out`, `cached_tokens_in`, `energy_millijoules`):
--
--   1. The energy cap of Neuralwatt (issue #794) is applied per REQUEST:
--      the honest figure is `Σ_calls min(raw_i, token_i)`, and
--      `Σ min(a_i, b_i) <= min(Σ a_i, Σ b_i)`. Summed counters therefore
--      cannot be re-split after a hold, and seeding one aggregate entry
--      overstates the billed energy of every prior attempt.
--   2. The counters are the COMPLETION total (written by
--      `record_worker_telemetry`). A worker that died between that write and
--      `mark_succeeded` left a total that already covers the whole job; seeding
--      a re-drive from it counted the stored-chunk replay a second time.
--
-- The ledger is append-only and is the ONLY seed of a re-drive. It is never
-- cleared: every entry describes a request the provider actually billed, which
-- stays true after a retry, a re-drive or a chunk-set invalidation.
ALTER TABLE ai_import.ai_import_job
    ADD COLUMN billed_calls JSONB NOT NULL DEFAULT '[]'::jsonb;

COMMENT ON COLUMN ai_import.ai_import_job.billed_calls IS
    'Per-request billed-call ledger (issue #970): one element per paid provider request of every attempt, in billing order. Append-only; the seed a re-drive resumes the accounting from (issues #794/#967).';
