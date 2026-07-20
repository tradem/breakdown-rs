// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors

//! Tier-3 / Tier-4 integration tests for the membership write path.
//!
//! These black-box tests drive the full `command → SierraDB → projector →
//! PostgreSQL projection → read-back` chain (ADR-016) against ephemeral
//! containers managed by `testcontainers`, mirroring
//! `audit_projector_tests.rs`. They are the membership analogue of the
//! `block-membership` spec's write-side acceptance criteria (task 10.5).

mod fixtures;

use std::sync::Arc;
use std::time::Duration;

use anyhow::{anyhow, bail, Result};
use breakdown_core::membership::events::MembershipEvent;
use breakdown_core::membership::views::{MembershipStateKind, MembershipView};
use breakdown_core::membership::{
    AcceptInvitation, BootstrapOwner, GrantRole, InviteMember, LeaveBlock, MembershipCommands,
    MembershipRepository, RemoveMember, Role,
};
use breakdown_core::shared::{BlockId, UserId};
use infra::event_store::MembershipCommandsImpl;
use infra::projectors::spawn_membership_projector;
use infra::queries::MembershipRepositoryImpl;
use kameo_es::command_service::CommandService;
use redis::Client as RedisClient;
use sqlx::PgPool;
use testcontainers::ContainerAsync;
use testcontainers_modules::postgres::Postgres;
use uuid::Uuid;

/// Bounded-retry window for the projector to catch up (ADR-015 eventual
/// consistency). Mirrors the scene/audit projector integration tests.
const PROJECTION_DEADLINE: Duration = Duration::from_secs(15);
const POLL_INTERVAL: Duration = Duration::from_millis(150);

/// Wait until the membership projection has at least `min` rows for `block_id`.
async fn await_membership_count(
    repo: &MembershipRepositoryImpl,
    block_id: BlockId,
    min: usize,
) -> Result<Vec<MembershipView>> {
    let deadline = std::time::Instant::now() + PROJECTION_DEADLINE;
    loop {
        let members = repo
            .list_by_block(block_id, 100, 0)
            .await
            .map_err(|e| anyhow!(e.to_string()))?;
        if members.len() >= min {
            return Ok(members);
        }
        if std::time::Instant::now() < deadline {
            tokio::time::sleep(POLL_INTERVAL).await;
        } else {
            bail!(
                "projection lag: membership rows for Block({}) = {} (expected >= {min}) \
                 within {PROJECTION_DEADLINE:?}",
                block_id.0,
                members.len()
            );
        }
    }
}

/// Wait until `user_id`'s projected role equals `expected` (role-change lag).
async fn await_member_role(
    repo: &MembershipRepositoryImpl,
    block_id: BlockId,
    user_id: UserId,
    expected: Role,
) -> Result<MembershipView> {
    let deadline = std::time::Instant::now() + PROJECTION_DEADLINE;
    loop {
        if let Some(m) = repo
            .find(block_id, user_id.clone())
            .await
            .map_err(|e| anyhow!(e.to_string()))?
        {
            if m.role == expected {
                return Ok(m);
            }
        }
        if std::time::Instant::now() < deadline {
            tokio::time::sleep(POLL_INTERVAL).await;
        } else {
            bail!(
                "projection lag: {user_id:?} role not updated to {expected:?} \
                 within {PROJECTION_DEADLINE:?}"
            );
        }
    }
}

/// Wait until `user_id` is no longer present in the projection (removal lag).
async fn await_member_absent(
    repo: &MembershipRepositoryImpl,
    block_id: BlockId,
    user_id: UserId,
) -> Result<()> {
    let deadline = std::time::Instant::now() + PROJECTION_DEADLINE;
    loop {
        let present = repo
            .find(block_id, user_id.clone())
            .await
            .map_err(|e| anyhow!(e.to_string()))?
            .is_some();
        if !present {
            return Ok(());
        }
        if std::time::Instant::now() < deadline {
            tokio::time::sleep(POLL_INTERVAL).await;
        } else {
            bail!(
                "projection lag: {user_id:?} still present after removal \
                 within {PROJECTION_DEADLINE:?}"
            );
        }
    }
}

/// Spin up Postgres + SierraDB + the membership projector, and a SierraDB-backed
/// `CommandService` (full command → SierraDB → projector → PG chain).
async fn init_membership() -> Result<(
    PgPool,
    CommandService,
    ContainerAsync<Postgres>,
    ContainerAsync<fixtures::SierraDbImage>,
)> {
    let (pool, pg_guard) = fixtures::spawn_postgres().await?;
    let (sierra_client, _sierra_conn, sierra_guard) = fixtures::spawn_sierradb().await?;

    // Spawn the membership projector (subscribes to `membership-*` streams).
    let _mp = spawn_membership_projector(pool.clone(), Arc::clone(&sierra_client)).await?;
    // Let the subscription settle before appending events.
    tokio::time::sleep(Duration::from_millis(500)).await;

    let cmd_service = CommandService::new(sierra_client.get_multiplexed_tokio_connection().await?);
    Ok((pool, cmd_service, pg_guard, sierra_guard))
}

/// EAPPEND a `MembershipEvent` to a SierraDB stream (CBOR payload), mirroring
/// the audit projector round-trip helper.
async fn eappend_membership(
    client: &Arc<RedisClient>,
    stream_id: &str,
    event_name: &str,
    expected_version: &str,
    event: &MembershipEvent,
) -> Result<()> {
    let mut payload = Vec::new();
    ciborium::into_writer(event, &mut payload).map_err(|e| anyhow!("CBOR encode failed: {e}"))?;
    let now_ms = chrono::Utc::now().timestamp_millis().try_into().unwrap_or(0u64);
    let mut conn = client.get_multiplexed_tokio_connection().await?;
    let _resp: redis::Value = redis::cmd("EAPPEND")
        .arg(stream_id)
        .arg(event_name)
        .arg("EXPECTED_VERSION")
        .arg(expected_version)
        .arg("PAYLOAD")
        .arg(&payload)
        .arg("TIMESTAMP")
        .arg(now_ms.to_string().as_bytes())
        .query_async(&mut conn)
        .await
        .map_err(|e| anyhow!("EAPPEND {event_name} failed: {e}"))?;
    Ok(())
}

/// Tier-4: a full `BootstrapOwner` → `InviteMember` → `AcceptInvitation`
/// command sequence is written to SierraDB (via `MembershipCommandsImpl`) and
/// projected into the `projection_membership` read model (command → SierraDB →
/// projector → PG), then read back through `MembershipRepositoryImpl`.
#[tokio::test]
async fn command_invite_accept_round_trips_into_membership_projection() -> Result<()> {
    let (pool, cmd_svc, _pg, _sierra) = init_membership().await?;
    let membership = MembershipCommandsImpl::new(cmd_svc);
    let repo = MembershipRepositoryImpl::new(pool.clone());

    let block_id = BlockId::from_uuid(Uuid::now_v7());
    let owner = UserId::from_sub("owner-a");
    let invitee = UserId::from_sub("invitee-b");

    // Bootstrap the block's first (owner) member.
    membership
        .bootstrap_owner(
            owner.clone(),
            BootstrapOwner {
                block_id,
                user_id: owner.clone(),
                role: Role::CostumeAssistant,
            },
        )
        .await?;

    // Owner invites a second user (pending until accepted).
    membership
        .invite(
            owner.clone(),
            InviteMember {
                block_id,
                user_id: invitee.clone(),
                role: Role::CostumeDesigner,
            },
        )
        .await?;

    // Invitee accepts → becomes an active member with the invited role.
    membership
        .accept_invitation(
            invitee.clone(),
            AcceptInvitation {
                block_id,
                user_id: invitee.clone(),
            },
        )
        .await?;

    // Wait for the projection to reflect both active members.
    let members = await_membership_count(&repo, block_id, 2).await?;
    assert_eq!(members.len(), 2, "both members projected");

    // Owner: active, costume_assistant.
    let owner_view = repo
        .find(block_id, owner.clone())
        .await?
        .expect("owner must be projected");
    assert_eq!(owner_view.user_id, owner);
    assert_eq!(owner_view.role, Role::CostumeAssistant);
    assert_eq!(owner_view.state, MembershipStateKind::Active);

    // Invitee: active, costume_designer (role carried from the invitation).
    let invitee_view = repo
        .find(block_id, invitee.clone())
        .await?
        .expect("invitee must be projected");
    assert_eq!(invitee_view.user_id, invitee);
    assert_eq!(invitee_view.role, Role::CostumeDesigner);
    assert_eq!(invitee_view.state, MembershipStateKind::Active);

    Ok(())
}

/// Tier-4: a `GrantRole` → `RemoveMember` → `LeaveBlock` command sequence is
/// projected correctly — role replacement, full removal, and self-service
/// leave (the actor leaves themselves, not another member).
#[tokio::test]
async fn command_grant_remove_leave_round_trips_into_membership_projection() -> Result<()> {
    let (pool, cmd_svc, _pg, _sierra) = init_membership().await?;
    let membership = MembershipCommandsImpl::new(cmd_svc);
    let repo = MembershipRepositoryImpl::new(pool.clone());

    let block_id = BlockId::from_uuid(Uuid::now_v7());
    let owner = UserId::from_sub("owner-a");
    let member = UserId::from_sub("member-c");

    membership
        .bootstrap_owner(
            owner.clone(),
            BootstrapOwner {
                block_id,
                user_id: owner.clone(),
                role: Role::CostumeAssistant,
            },
        )
        .await?;
    membership
        .invite(
            owner.clone(),
            InviteMember {
                block_id,
                user_id: member.clone(),
                role: Role::CostumeAssistant,
            },
        )
        .await?;
    membership
        .accept_invitation(
            member.clone(),
            AcceptInvitation {
                block_id,
                user_id: member.clone(),
            },
        )
        .await?;

    // Owner grants the member a new role.
    membership
        .grant_role(
            owner.clone(),
            GrantRole {
                block_id,
                user_id: member.clone(),
                role: Role::WardrobeSupervisor,
            },
        )
        .await?;

    let granted = await_member_role(&repo, block_id, member.clone(), Role::WardrobeSupervisor).await?;
    assert_eq!(granted.state, MembershipStateKind::Active);

    // Owner removes the member entirely.
    membership
        .remove_member(
            owner.clone(),
            RemoveMember {
                block_id,
                user_id: member.clone(),
            },
        )
        .await?;
    await_member_absent(&repo, block_id, member.clone()).await?;

    // Owner leaves via self-service.
    membership
        .leave_block(owner.clone(), LeaveBlock { block_id })
        .await?;
    await_member_absent(&repo, block_id, owner.clone()).await?;

    // The block is now empty.
    let remaining = repo
        .list_by_block(block_id, 100, 0)
        .await
        .map_err(|e| anyhow!(e.to_string()))?;
    assert!(remaining.is_empty(), "no members should remain");

    Ok(())
}

/// Tier-3: projector idempotency under event redelivery (ADR-016).
///
/// Appends `OwnerBootstrapped` for the owner, then re-appends the *same* event
/// (redelivery — a fresh SierraDB append with a new `event.id`), then appends a
/// *distinct* `MemberInvited`. Because the membership projector upserts on the
/// `(block_id, user_id)` key, the redelivery does not create a duplicate row:
/// exactly 2 membership rows appear (owner active + invitee pending).
#[tokio::test]
async fn membership_projector_is_idempotent_under_redelivery() -> Result<()> {
    let (pool, _pg) = fixtures::spawn_postgres().await?;
    let (redis_client, _sierra_conn, _sierra) = fixtures::spawn_sierradb().await?;

    let _mp = spawn_membership_projector(pool.clone(), Arc::clone(&redis_client)).await?;
    let repo = MembershipRepositoryImpl::new(pool);

    let block_id = Uuid::now_v7();
    let owner = UserId::from_sub("owner-a");
    let invitee = UserId::from_sub("invitee-b");
    // Stream id == block id (category "membership"), matching the command path.
    let stream_id = format!("membership-{}", block_id);

    let bootstrap = MembershipEvent::OwnerBootstrapped {
        block_id: BlockId::from_uuid(block_id),
        user_id: owner.clone(),
        role: Role::CostumeAssistant,
    };

    eappend_membership(&redis_client, &stream_id, "OwnerBootstrapped", "EMPTY", &bootstrap).await?;
    let members = await_membership_count(&repo, BlockId::from_uuid(block_id), 1).await?;
    assert_eq!(members.len(), 1, "first bootstrap projected");
    assert_eq!(members[0].state, MembershipStateKind::Active);

    // Redelivery of the same logical event (fresh SierraDB append → new event.id).
    eappend_membership(&redis_client, &stream_id, "OwnerBootstrapped", "0", &bootstrap).await?;

    let invite = MembershipEvent::MemberInvited {
        block_id: BlockId::from_uuid(block_id),
        user_id: invitee.clone(),
        role: Role::CostumeDesigner,
    };
    eappend_membership(&redis_client, &stream_id, "MemberInvited", "1", &invite).await?;

    let members = await_membership_count(&repo, BlockId::from_uuid(block_id), 2).await?;
    assert_eq!(
        members.len(),
        2,
        "redelivery must not duplicate the membership row"
    );

    let owner_row = members
        .iter()
        .find(|m| m.user_id == owner)
        .expect("owner projected");
    assert_eq!(owner_row.state, MembershipStateKind::Active);
    assert_eq!(owner_row.role, Role::CostumeAssistant);

    let invitee_row = members
        .iter()
        .find(|m| m.user_id == invitee)
        .expect("invitee projected");
    assert_eq!(invitee_row.state, MembershipStateKind::Pending);
    assert_eq!(invitee_row.role, Role::CostumeDesigner);

    Ok(())
}
