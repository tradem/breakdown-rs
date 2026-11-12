// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

//! Project-membership projection handler: `ProjectMembershipEvent` ->
//! `projection_project_membership`.
//!
//! `role` and `state` are written as **plain tokens** (`costume_designer`,
//! `active`), not as their JSON forms — the same reason as
//! `MembershipProjector`: the authorization predicates compare these columns
//! against plain SQL string literals (`pm.state = 'active'`,
//! `pm.role IN (...)`), and JSON quotes would match nothing.
//! `Role::as_str` is the storage representation.
//!
//! ## Idempotency
//!
//! The upsert is keyed by `(project_id, user_id)` and **version-guarded**:
//! `WHERE stream_version < EXCLUDED.stream_version` (mirroring
//! `ReservationProjector`). A redelivered event therefore cannot regress the
//! row, and — the case that matters — a replayed *older* grant cannot
//! resurrect a revoked grant. The version comes from the `kameo_es` event
//! envelope (`Event::stream_version`); the `ProjectMembershipEvent` payloads
//! carry none.

use super::PROJECTOR_VERSION;
use breakdown_core::project_membership::ProjectMembership;
use breakdown_core::project_membership::events::ProjectMembershipEvent;
use breakdown_core::shared::EventMetadata;
use kameo_es::Event;
use kameo_es::event_handler::{EntityEventHandler, EventHandler};
use sqlx::{Postgres, Transaction};

/// Storage token of a revoked project-scoped grant.
///
/// Deliberately a local literal: `MembershipStateKind` only models the
/// block-scoped life cycle (`Pending`/`Active`, a removal deletes the row), so
/// there is no core variant to borrow. The predicates only ever match
/// `'active'`, so a revoked row is inert.
const REVOKED_STATE: &str = "revoked";

/// Idempotent projector for the `ProjectMembership` aggregate.
#[derive(Clone, Default, Debug)]
pub struct ProjectMembershipProjector;

impl<'a> EventHandler<Transaction<'a, Postgres>> for ProjectMembershipProjector {
    type Error = sqlx::Error;
}

impl<'a> EntityEventHandler<ProjectMembership, Transaction<'a, Postgres>>
    for ProjectMembershipProjector
{
    async fn handle(
        &mut self,
        ctx: &mut Transaction<'a, Postgres>,
        _id: uuid::Uuid,
        event: Event<ProjectMembershipEvent, EventMetadata>,
    ) -> Result<(), Self::Error> {
        let updated_at = event.timestamp;
        let stream_version = event.stream_version as i64;

        match event.data {
            ProjectMembershipEvent::ProjectOwnerBootstrapped {
                project_id,
                user_id,
                role,
            }
            | ProjectMembershipEvent::ProjectRoleGranted {
                project_id,
                user_id,
                role,
            } => {
                // Both grant shapes become the same projected row: an ACTIVE
                // project-scoped role. `joined_at` is deliberately not part of
                // the update branch — a re-grant keeps the first join date.
                sqlx::query(
                    r#"
                    INSERT INTO projection_project_membership
                        (project_id, user_id, role, state, joined_at, updated_at,
                         projector_version, stream_version)
                    VALUES ($1, $2, $3, 'active', $4, $4, $5, $6)
                    ON CONFLICT (project_id, user_id) DO UPDATE SET
                        role = EXCLUDED.role,
                        state = 'active',
                        updated_at = EXCLUDED.updated_at,
                        projector_version = EXCLUDED.projector_version,
                        stream_version = EXCLUDED.stream_version
                    -- Redelivery idempotency: never regress the version, so a
                    -- replayed older grant cannot resurrect a revoked one.
                    WHERE projection_project_membership.stream_version < EXCLUDED.stream_version
                    "#,
                )
                .bind(project_id.0)
                .bind(user_id.as_str())
                .bind(role.as_str())
                .bind(updated_at)
                .bind(PROJECTOR_VERSION)
                .bind(stream_version)
                .execute(&mut **ctx)
                .await?;
            }
            ProjectMembershipEvent::ProjectRoleRevoked {
                project_id,
                user_id,
            } => {
                // A revocation is a state transition, not a row delete (see
                // migration 20261111000001): the audit trail of the grant
                // stays readable and the authz predicates stop matching.
                sqlx::query(
                    r#"
                    UPDATE projection_project_membership
                    SET state = $3,
                        updated_at = $4,
                        projector_version = $5,
                        stream_version = $6
                    WHERE project_id = $1
                      AND user_id = $2
                      AND stream_version < $6
                    "#,
                )
                .bind(project_id.0)
                .bind(user_id.as_str())
                .bind(REVOKED_STATE)
                .bind(updated_at)
                .bind(PROJECTOR_VERSION)
                .bind(stream_version)
                .execute(&mut **ctx)
                .await?;
            }
        }

        Ok(())
    }
}
