-- SPDX-License-Identifier: AGPL-3.0
-- Copyright (C) 2024-2026 Breakdown RS Contributors
-- Co-authored-by: deepseek-v4-flash (opencode-go)

-- ADR-020 D4: `projector_version` on the read model.
--
-- Every projector stamps its `PROJECTOR_VERSION` constant (crates/infra/src/
-- projectors/mod.rs) on the rows it writes. The event-schema fixture-replay
-- contract tests (crates/integration-tests/tests/event_fixture_contract_tests.rs)
-- replay captured event fixtures through the *current* projector binary and
-- assert the projection, including `projector_version` — so a new event shape
-- unreadable by a deployed older projector becomes a deploy-order failure
-- caught by CI instead of a silent audit gap in production.
--
-- Strictly additive (ADR-021 D6): new nullable-with-default column, never
-- rename/drop within an open API deprecation window.

ALTER TABLE projection_season             ADD COLUMN projector_version BIGINT NOT NULL DEFAULT 0;
ALTER TABLE projection_block              ADD COLUMN projector_version BIGINT NOT NULL DEFAULT 0;
ALTER TABLE projection_episode            ADD COLUMN projector_version BIGINT NOT NULL DEFAULT 0;
ALTER TABLE projection_scene              ADD COLUMN projector_version BIGINT NOT NULL DEFAULT 0;
ALTER TABLE projection_scene_character    ADD COLUMN projector_version BIGINT NOT NULL DEFAULT 0;
ALTER TABLE projection_scene_shooting_day ADD COLUMN projector_version BIGINT NOT NULL DEFAULT 0;
ALTER TABLE projection_shooting_day       ADD COLUMN projector_version BIGINT NOT NULL DEFAULT 0;
ALTER TABLE projection_character          ADD COLUMN projector_version BIGINT NOT NULL DEFAULT 0;
ALTER TABLE projection_costume            ADD COLUMN projector_version BIGINT NOT NULL DEFAULT 0;
ALTER TABLE projection_costume_detail     ADD COLUMN projector_version BIGINT NOT NULL DEFAULT 0;
ALTER TABLE projection_costume_photo      ADD COLUMN projector_version BIGINT NOT NULL DEFAULT 0;
ALTER TABLE projection_costume_category   ADD COLUMN projector_version BIGINT NOT NULL DEFAULT 0;
ALTER TABLE projection_membership         ADD COLUMN projector_version BIGINT NOT NULL DEFAULT 0;
ALTER TABLE projection_audit              ADD COLUMN projector_version BIGINT NOT NULL DEFAULT 0;
ALTER TABLE projection_settings           ADD COLUMN projector_version BIGINT NOT NULL DEFAULT 0;
ALTER TABLE projection_scene_shoot        ADD COLUMN projector_version BIGINT NOT NULL DEFAULT 0;
ALTER TABLE projection_photo              ADD COLUMN projector_version BIGINT NOT NULL DEFAULT 0;
ALTER TABLE projection_photo_variant      ADD COLUMN projector_version BIGINT NOT NULL DEFAULT 0;
ALTER TABLE projection_continuity_photo   ADD COLUMN projector_version BIGINT NOT NULL DEFAULT 0;
ALTER TABLE ai_import.projection_ai_config        ADD COLUMN projector_version BIGINT NOT NULL DEFAULT 0;
ALTER TABLE ai_import.projection_ai_import_mapping ADD COLUMN projector_version BIGINT NOT NULL DEFAULT 0;
