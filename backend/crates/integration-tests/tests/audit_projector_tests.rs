// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors

mod fixtures;

use std::sync::Arc;
use std::time::Duration;

use anyhow::{Result, anyhow, bail};
use breakdown_core::audit::ports::AuditRepository as _;
use breakdown_core::audit::views::AuditEntry;
use breakdown_core::membership::Role;
use breakdown_core::membership::events::MembershipEvent;
use breakdown_core::shared::{BlockId, UserId};
use chrono::Utc;
use infra::projectors::spawn_audit_projector;
use infra::queries::AuditRepositoryImpl;
use redis::Client as RedisClient;
use serde_json::json;
use uuid::Uuid;

/// Bounded-retry window for the projector to catch up (ADR-015 eventual
/// consistency). Mirrors the scene projector integration tests.
const PROJECTION_DEADLINE: Duration = Duration::from_secs(15);
const POLL_INTERVAL: Duration = Duration::from_millis(150);

/// Wait until the audit projection has at least `min` rows for `block_id`.
async fn await_audit_count(
    repo: &AuditRepositoryImpl,
    block_id: Uuid,
    min: usize,
) -> Result<Vec<AuditEntry>> {
    let deadline = std::time::Instant::now() + PROJECTION_DEADLINE;
    loop {
        let entries = repo
            .list_by_block(BlockId::from_uuid(block_id), 50, 0)
            .await
            .map_err(|e| anyhow!(e.to_string()))?;
        if entries.len() >= min {
            return Ok(entries);
        }
        if std::time::Instant::now() < deadline {
            tokio::time::sleep(POLL_INTERVAL).await;
        } else {
            bail!(
                "projection lag: audit rows for Block({block_id}) = {} (expected >= {min}) \
                 within {PROJECTION_DEADLINE:?}",
                entries.len()
            );
        }
    }
}

/// EAPPEND a `MembershipEvent` to a SierraDB stream (CBOR payload), mirroring
/// the scene projector round-trip helper.
async fn eappend_membership(
    client: &Arc<RedisClient>,
    stream_id: &str,
    event_name: &str,
    expected_version: &str,
    event: &MembershipEvent,
) -> Result<()> {
    let mut payload = Vec::new();
    ciborium::into_writer(event, &mut payload).map_err(|e| anyhow!("CBOR encode failed: {e}"))?;
    let now_ms = Utc::now().timestamp_millis().try_into().unwrap_or(0u64);
    let mut conn = client.get_multiplexed_async_connection().await?;
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

/// Tier-4: a `BlockMembership` event appended to SierraDB is projected into the
/// generic `projection_audit` read model (command → SierraDB → projector → PG).
#[tokio::test]
async fn eappend_owner_bootstrapped_round_trips_into_audit() -> Result<()> {
    let (pool, _pg) = crate::fixtures::spawn_postgres().await?;
    let (redis_client, _sierra_conn, _sierra) = crate::fixtures::spawn_sierradb().await?;

    let _audit_ref = spawn_audit_projector(pool.clone(), Arc::clone(&redis_client)).await?;

    let repo = AuditRepositoryImpl::new(pool);

    let block_id = Uuid::now_v7();
    let user_a = UserId::from_sub("owner-a");
    let agg_id = Uuid::now_v7();
    let stream_id = format!("membership-{agg_id}");

    let event = MembershipEvent::OwnerBootstrapped {
        block_id: BlockId::from_uuid(block_id),
        user_id: user_a.clone(),
        role: Role::CostumeAssistant,
    };

    eappend_membership(
        &redis_client,
        &stream_id,
        "OwnerBootstrapped",
        "EMPTY",
        &event,
    )
    .await?;

    let entries = await_audit_count(&repo, block_id, 1).await?;
    assert_eq!(entries.len(), 1, "exactly one audit row expected");
    let row = &entries[0];
    assert_eq!(row.entity_type, "membership");
    assert_eq!(row.event_type, "OwnerBootstrapped");
    assert_eq!(row.block_id, Some(BlockId::from_uuid(block_id)));
    // Raw EAPPEND carries no command metadata, so the actor dimension is NULL.
    // Actor capture is exercised end-to-end via the command adapter
    // (`MembershipCommandsImpl` sets `MembershipMetadata.actor`).
    assert!(
        row.actor.is_none(),
        "actor comes from command metadata, not raw EAPPEND"
    );
    // `MembershipEvent` serializes as an externally-tagged enum, so the payload
    // is `{"OwnerBootstrapped": { ...fields... }}`.
    assert_eq!(
        row.payload,
        json!({
            "OwnerBootstrapped": {
                "block_id": block_id.to_string(),
                "user_id": "owner-a",
                "role": "costume_assistant"
            }
        }),
        "audit payload must capture the full event data"
    );

    Ok(())
}

/// Tier-3: projector idempotency under event redelivery (ADR-016).
///
/// Appends `OwnerBootstrapped` for user A, then re-appends the *same* event
/// (redelivery — a fresh SierraDB append with a new `event.id`), then appends a
/// *distinct* `MemberInvited` for user B. If redelivery were not idempotent the
/// audit log would contain 3 rows; because the projector dedupes on the
/// deterministic `event_key`, exactly 2 rows appear (the distinct event plus the
/// first bootstrap — the redelivery is dropped). Waiting for the distinct third
/// event to be projected proves the projector processed the redelivery.
#[tokio::test]
async fn audit_projector_is_idempotent_under_redelivery() -> Result<()> {
    let (pool, _pg) = crate::fixtures::spawn_postgres().await?;
    let (redis_client, _sierra_conn, _sierra) = crate::fixtures::spawn_sierradb().await?;

    let _audit_ref = spawn_audit_projector(pool.clone(), Arc::clone(&redis_client)).await?;

    let repo = AuditRepositoryImpl::new(pool);

    let block_id = Uuid::now_v7();
    let user_a = UserId::from_sub("owner-a");
    let user_b = UserId::from_sub("invitee-b");
    let agg_id = Uuid::now_v7();
    let stream_id = format!("membership-{agg_id}");

    let bootstrap = MembershipEvent::OwnerBootstrapped {
        block_id: BlockId::from_uuid(block_id),
        user_id: user_a.clone(),
        role: Role::CostumeAssistant,
    };

    // 1. First append (EXPECTED_VERSION EMPTY → version 0→1).
    eappend_membership(
        &redis_client,
        &stream_id,
        "OwnerBootstrapped",
        "EMPTY",
        &bootstrap,
    )
    .await?;
    let entries = await_audit_count(&repo, block_id, 1).await?;
    assert_eq!(entries.len(), 1, "first bootstrap projected");
    assert_eq!(entries[0].event_type, "OwnerBootstrapped");

    // 2. Redelivery: same logical event, fresh SierraDB append (version 1→2).
    eappend_membership(
        &redis_client,
        &stream_id,
        "OwnerBootstrapped",
        "0",
        &bootstrap,
    )
    .await?;

    // 3. Distinct event to prove the projector processed through the redelivery.
    let invite = MembershipEvent::MemberInvited {
        block_id: BlockId::from_uuid(block_id),
        user_id: user_b.clone(),
        role: Role::CostumeDesigner,
    };
    eappend_membership(&redis_client, &stream_id, "MemberInvited", "1", &invite).await?;

    // Projector must have processed all three appends; the redelivery is deduped.
    let entries = await_audit_count(&repo, block_id, 2).await?;
    assert_eq!(
        entries.len(),
        2,
        "redelivery must not duplicate the audit row"
    );

    let bootstrap_count = entries
        .iter()
        .filter(|e| e.event_type == "OwnerBootstrapped")
        .count();
    assert_eq!(
        bootstrap_count, 1,
        "OwnerBootstrapped must appear exactly once (redelivery deduped)"
    );
    assert!(
        entries.iter().any(|e| e.event_type == "MemberInvited"),
        "distinct MemberInvited must be projected as its own row"
    );

    Ok(())
}
