-- SPDX-License-Identifier: AGPL-3.0
-- Copyright (C) 2024-2026 Breakdown RS Contributors
-- Co-authored-by: glm-5.3 (neuralwatt)

-- Operator zero-data-retention attestation per AI configuration (issue #968,
-- ADR-041 `D2`).
--
-- Some OpenAI-compatible providers carry the ZDR guarantee only as an
-- ACCOUNT-level switch (Nebius Token Factory: "ZDR Mode" in the organization
-- settings, admin-only, off by default). Rust cannot observe that setting, so
-- the provider's static `vision_egress_policy` deliberately declares
-- `zero_data_retention: false` — a boolean the code cannot verify must never be
-- asserted as `true` — and the operator attests the account setting on the AI
-- configuration instead. `vision_egress_policy_for_config(provider,
-- zdr_attested)` is the only place that turns the attestation into an effective
-- policy, and it can lift ONLY the ZDR flag: the no-training and EU-residency
-- requirements always come from the provider declaration.
--
-- Default FALSE: every configuration written before this migration, and every
-- request from a client that does not send the field, attests nothing and keeps
-- the fail-closed gate.
ALTER TABLE ai_import.projection_ai_config
    ADD COLUMN zdr_attested BOOLEAN NOT NULL DEFAULT FALSE;

COMMENT ON COLUMN ai_import.projection_ai_config.zdr_attested IS
    'Operator attestation that the provider account has zero data retention enabled (issue #968). Read by vision_egress_policy_for_config before any page image egress; never a secret.';
