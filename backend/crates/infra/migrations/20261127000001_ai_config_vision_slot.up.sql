-- SPDX-License-Identifier: AGPL-3.0
-- Copyright (C) 2024-2026 Breakdown RS Contributors
-- Co-authored-by: deepseek-v4.1-flash (opencode-go)

-- Dedicated Vision slot (issue #1013).
--
-- The AI configuration had no way to name the provider/model/credential that
-- carries PAGE IMAGES: the page-streaming schedule extractor rendered a page
-- PNG and sent it to the *assistant* (text) model. A text-only assistant model
-- failed on the first paid page call, a vision-capable one billed the 100+
-- text chunks of a Drehbuch at image rates. `image_model` is the diffusion
-- GENERATION seam (#673) and is read by no worker, so it is deliberately not
-- reused here.
--
-- All four columns are nullable/false-defaulted: a row with no vision slot
-- behaves exactly like a pre-#1013 configuration ("use the assistant pair").

ALTER TABLE ai_import.projection_ai_config
    ADD COLUMN IF NOT EXISTS vision_provider TEXT,
    ADD COLUMN IF NOT EXISTS vision_model TEXT,
    ADD COLUMN IF NOT EXISTS vision_vault_key_id TEXT,
    ADD COLUMN IF NOT EXISTS vision_zdr_attested BOOLEAN NOT NULL DEFAULT FALSE;

COMMENT ON COLUMN ai_import.projection_ai_config.vision_provider IS
    'Optional Vision-slot host (issue #1013), e.g. ovhcloud | scaleway | eurouter | nebius | ollama. NULL = use the assistant pair.';
COMMENT ON COLUMN ai_import.projection_ai_config.vision_model IS
    'Vision (page-image) model ID of the vision provider (issue #1013), e.g. qwen3-vl-30b-a3b. NULL = use the assistant model.';
COMMENT ON COLUMN ai_import.projection_ai_config.vision_vault_key_id IS
    'Vault key of the vision provider credential (issue #1013): may equal vault_key_id only when the vision provider IS the extraction provider (same-key reuse).';
COMMENT ON COLUMN ai_import.projection_ai_config.vision_zdr_attested IS
    'Operator attestation that the VISION provider account keeps no data (issue #1013, #968 semantics). Bound to vision_vault_key_id: a replaced vision credential drops it.';
