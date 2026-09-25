-- SPDX-License-Identifier: AGPL-3.0
-- Copyright (C) 2024-2026 Breakdown RS Contributors
-- Co-authored-by: space-bunny-free (opencode-go)
--
-- Issue #528: the API-edge provider-binding pre-check of an AI-config
-- provider replacement resolves the credential reference behind an opaque
-- `vault_key_id`. Index that column so the read-model lookup does not
-- degrade into a sequential scan as credentials accumulate.
CREATE INDEX IF NOT EXISTS idx_projection_settings_vault_key_id
    ON projection_settings (vault_key_id);
