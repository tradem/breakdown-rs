-- SPDX-License-Identifier: AGPL-3.0
-- Copyright (C) 2024-2026 Breakdown RS Contributors
-- Co-authored-by: qwen3.8-flash (opencode-go)

-- Reverses the key extension. Restoring the old primary key fails while
-- character/costume rows exist (several rows then share (preview_id,
-- draft_ref)), which is the honest signal that applied figures and costumes must
-- be deleted before rolling the mapping table back.
ALTER TABLE ai_import.projection_ai_import_mapping
    DROP CONSTRAINT projection_ai_import_mapping_pkey;

ALTER TABLE ai_import.projection_ai_import_mapping
    ADD PRIMARY KEY (preview_id, draft_ref);

ALTER TABLE ai_import.projection_ai_import_mapping
    DROP COLUMN ordinal;
