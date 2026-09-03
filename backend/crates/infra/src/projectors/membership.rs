// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4-flash (opencode-go)
// Co-authored-by: hy4-preview (opencode-go)

//! Membership projection handler: `MembershipEvent` -> `projection_membership`.
//!
//! `role` and `state` are written as **plain tokens** (`costume_assistant`,
//! `active`), not as their JSON forms (`"costume_assistant"`, `"active"`):
//! the membership authorization predicates compare these columns against
//! plain SQL string literals (`m.state = 'active'`, `m.role IN (...)`), and
//! the JSON quotes made those comparisons match nothing. The wire format of
//! `MembershipView` is unaffected — it is still serde-JSON. See
//! `Role::as_str` / `MembershipStateKind::as_str`.

use super::PROJECTOR_VERSION;
use breakdown_core::membership::MembershipMetadata;
use breakdown_core::membership::aggregate::BlockMembership;
use breakdown_core::membership::events::MembershipEvent;
use breakdown_core::membership::views::MembershipStateKind;
use kameo_es::Event;
use kameo_es::event_handler::{EntityEventHandler, EventHandler};
use sqlx::{Postgres, Transaction};

/// Idempotent projector for the `BlockMembership` aggregate.
///
/// Redelivery is safe: `MemberInvited` is an idempotent upsert; accept/grant
/// are idempotent `UPDATE`s keyed by `(block_id, user_id)`; `MemberRemoved` is a
/// `DELETE`. Replaying the same event yields identical projection state.
#[derive(Clone, Default, Debug)]
pub struct MembershipProjector;

impl<'a> EventHandler<Transaction<'a, Postgres>> for MembershipProjector {
    type Error = sqlx::Error;
}

impl<'a> EntityEventHandler<BlockMembership, Transaction<'a, Postgres>> for MembershipProjector {
    async fn handle(
        &mut self,
        ctx: &mut Transaction<'a, Postgres>,
        _id: uuid::Uuid,
        event: Event<MembershipEvent, MembershipMetadata>,
    ) -> Result<(), Self::Error> {
        let updated_at = event.timestamp;

        match event.data {
            MembershipEvent::MemberInvited {
                block_id,
                user_id,
                role,
            } => {
                let role_token = role.as_str();
                let state_token = MembershipStateKind::Pending.as_str();
                sqlx::query(
                    r#"
                    INSERT INTO projection_membership
                        (block_id, user_id, role, state, joined_at, updated_at)
                    VALUES ($1, $2, $3, $4, $5, $6)
                    ON CONFLICT (block_id, user_id) DO UPDATE SET
                        role = EXCLUDED.role,
                        state = EXCLUDED.state,
                        joined_at = EXCLUDED.joined_at,
                        updated_at = EXCLUDED.updated_at
                    "#,
                )
                .bind(block_id.0)
                .bind(user_id.as_str())
                .bind(role_token)
                .bind(state_token)
                .bind(updated_at)
                .bind(updated_at)
                .execute(&mut **ctx)
                .await?;
            }
            MembershipEvent::InvitationAccepted {
                block_id,
                user_id,
                role,
            } => {
                let role_token = role.as_str();
                let state_token = MembershipStateKind::Active.as_str();
                sqlx::query(
                    r#"
                    UPDATE projection_membership
                    SET role = $3, state = $4, joined_at = $5, updated_at = $5
                    WHERE block_id = $1 AND user_id = $2
                    "#,
                )
                .bind(block_id.0)
                .bind(user_id.as_str())
                .bind(role_token)
                .bind(state_token)
                .bind(updated_at)
                .execute(&mut **ctx)
                .await?;
            }
            MembershipEvent::RoleGranted {
                block_id,
                user_id,
                role,
            } => {
                let role_token = role.as_str();
                sqlx::query(
                    r#"
                    UPDATE projection_membership
                    SET role = $3, updated_at = $4
                    WHERE block_id = $1 AND user_id = $2
                    "#,
                )
                .bind(block_id.0)
                .bind(user_id.as_str())
                .bind(role_token)
                .bind(updated_at)
                .execute(&mut **ctx)
                .await?;
            }
            MembershipEvent::MemberRemoved { block_id, user_id } => {
                sqlx::query(
                    r#"
                    DELETE FROM projection_membership
                    WHERE block_id = $1 AND user_id = $2
                    "#,
                )
                .bind(block_id.0)
                .bind(user_id.as_str())
                .execute(&mut **ctx)
                .await?;
            }
            MembershipEvent::OwnerBootstrapped {
                block_id,
                user_id,
                role,
            } => {
                // Treated exactly like an accepted invitation: the bootstrapped
                // user becomes an active member with `role`. Idempotent upsert
                // keyed by `(block_id, user_id)` keeps redelivery safe.
                let role_token = role.as_str();
                let state_token = MembershipStateKind::Active.as_str();
                sqlx::query(
                    r#"
                    INSERT INTO projection_membership
                        (block_id, user_id, role, state, joined_at, projector_version, updated_at)
                    VALUES ($1, $2, $3, $4, $5, $6, $7)
                    ON CONFLICT (block_id, user_id) DO UPDATE SET
                        role = EXCLUDED.role,
                        state = EXCLUDED.state,
                        joined_at = EXCLUDED.joined_at,
                        projector_version = EXCLUDED.projector_version,
                        updated_at = EXCLUDED.updated_at
                    "#,
                )
                .bind(block_id.0)
                .bind(user_id.as_str())
                .bind(role_token)
                .bind(state_token)
                .bind(updated_at)
                .bind(PROJECTOR_VERSION)
                .bind(updated_at)
                .execute(&mut **ctx)
                .await?;
            }
        }

        Ok(())
    }
}
