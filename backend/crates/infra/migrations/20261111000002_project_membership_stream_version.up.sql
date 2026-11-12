-- SPDX-License-Identifier: AGPL-3.0
-- Copyright (C) 2024-2026 Breakdown RS Contributors
-- Co-authored-by: deepseek-v4.1-flash (opencode-go)
--
-- Redelivery idempotency for the project-scoped membership projection
-- (openspec/changes/project-scoped-membership, task 2.2).
--
-- The projector's grant/revoke statements are version-guarded
-- (`... WHERE stream_version < $N`, mirroring
-- `projection_number_reservation`): a replayed OLDER event must not resurrect a
-- revoked grant, and `projection_project_membership.projector_version` cannot
-- serve as the guard because it carries the read-model CONTRACT version
-- (`PROJECTOR_VERSION`), not the aggregate's stream position.
--
-- The `ProjectMembershipEvent` payloads carry no version field, so the guard
-- reads `kameo_es::Event::stream_version` from the envelope.
--
-- Added as a separate migration (not by editing 20261111000001) because that
-- one may already be applied — sqlx verifies migration checksums.

ALTER TABLE projection_project_membership
    ADD COLUMN IF NOT EXISTS stream_version BIGINT NOT NULL DEFAULT 0;
