-- SPDX-License-Identifier: AGPL-3.0
-- Copyright (C) 2024-2026 Breakdown RS Contributors
-- Co-authored-by: qwen3.8-flash (opencode-go)

-- openspec: ai-import-character-costumes (group 4)
--
-- `projection_ai_import_mapping` addressed a row by (preview_id, draft_ref),
-- which was sufficient while applying produced scenes only. One reviewed draft
-- row now produces several aggregates: its scene, the figures it names, and
-- each of its costumes. Two costumes of one figure inside one scene share every
-- part of the old key, so they would have resolved to a single mapping row and
-- the second costume would silently never have been created (design D4).
--
-- The discriminator `aggregate_kind` already existed but was not part of the
-- identity; it becomes part of the primary key together with a new `ordinal`.
--
-- Additive: existing rows keep their current `aggregate_kind` and gain ordinal
-- 0, which reproduces exactly the key they were already addressed by.

ALTER TABLE ai_import.projection_ai_import_mapping
    ADD COLUMN ordinal INTEGER NOT NULL DEFAULT 0;

ALTER TABLE ai_import.projection_ai_import_mapping
    DROP CONSTRAINT projection_ai_import_mapping_pkey;

ALTER TABLE ai_import.projection_ai_import_mapping
    ADD PRIMARY KEY (preview_id, draft_ref, aggregate_kind, ordinal);

COMMENT ON COLUMN ai_import.projection_ai_import_mapping.ordinal IS
    'Disambiguates rows that share draft_ref AND aggregate_kind — the costumes '
    'of one figure in one scene. Every other kind carries 0.';
