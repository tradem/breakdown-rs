-- SPDX-License-Identifier: AGPL-3.0
-- Copyright (C) 2024-2026 Breakdown RS Contributors
-- Co-authored-by: deepseek-v4-flash (opencode-go)

-- ADR-020 D4: drop the `projector_version` marker column again.
ALTER TABLE projection_season             DROP COLUMN projector_version;
ALTER TABLE projection_block              DROP COLUMN projector_version;
ALTER TABLE projection_episode            DROP COLUMN projector_version;
ALTER TABLE projection_scene              DROP COLUMN projector_version;
ALTER TABLE projection_scene_character    DROP COLUMN projector_version;
ALTER TABLE projection_scene_shooting_day DROP COLUMN projector_version;
ALTER TABLE projection_shooting_day       DROP COLUMN projector_version;
ALTER TABLE projection_character          DROP COLUMN projector_version;
ALTER TABLE projection_costume            DROP COLUMN projector_version;
ALTER TABLE projection_costume_detail     DROP COLUMN projector_version;
ALTER TABLE projection_costume_photo      DROP COLUMN projector_version;
ALTER TABLE projection_costume_category   DROP COLUMN projector_version;
ALTER TABLE projection_membership         DROP COLUMN projector_version;
ALTER TABLE projection_audit              DROP COLUMN projector_version;
ALTER TABLE projection_settings           DROP COLUMN projector_version;
ALTER TABLE projection_scene_shoot        DROP COLUMN projector_version;
ALTER TABLE projection_photo              DROP COLUMN projector_version;
ALTER TABLE projection_photo_variant      DROP COLUMN projector_version;
ALTER TABLE projection_continuity_photo   DROP COLUMN projector_version;
ALTER TABLE ai_import.projection_ai_config        DROP COLUMN projector_version;
ALTER TABLE ai_import.projection_ai_import_mapping DROP COLUMN projector_version;
