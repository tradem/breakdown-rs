-- SPDX-License-Identifier: AGPL-3.0
-- Copyright (C) 2024-2026 Breakdown RS Contributors

-- Projection column for AI provenance on scenes (issue #517, EU AI Act
-- Art. 50 transparency): `SceneSource` as structured JSONB, mirroring
-- `projection_shooting_day.source`. The projector writes the event's
-- discriminator on insert/redelivery.
--
-- Legacy rows (created before this migration) default to `Manual`. Scenes that
-- the AI script import created *before* #517 keep that default: Postgres holds
-- no reliable creation evidence to backfill them — the import workers dispatch
-- with the human actor (`Provenance::Human`, so `projection_audit` proves
-- nothing) and `ai_import.projection_ai_import_mapping` does not distinguish
-- create from update decisions (backfilling from it would mislabel manually
-- created scenes that merely received an AI update). The authoritative answer
-- lives only in the SierraDB `SceneCreated` event streams; a targeted relabel
-- (event-scan script or badge-time read) is intentionally deferred and
-- documented in the follow-up issue (see PR #540 review discussion).
ALTER TABLE projection_scene
    ADD COLUMN IF NOT EXISTS source JSONB NOT NULL DEFAULT '{"Manual":null}'::jsonb;
