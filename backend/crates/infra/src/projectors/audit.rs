// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors

//! Generic audit / journal projector.
//!
//! v1 captures the `membership` Bounded Context's events; the projection is
//! generic (`entity_type` + `payload` JSONB + nullable `series_id` tenant
//! dimension) so other contexts' events can be appended later without a
//! breaking migration. Idempotency under redelivery is guaranteed by using
//! the event store's stable per-event `id` as the primary key
//! (`ON CONFLICT (id) DO NOTHING`).

use breakdown_core::membership::aggregate::BlockMembership;
use breakdown_core::membership::events::MembershipEvent;
use breakdown_core::membership::MembershipMetadata;
use kameo_es::event_handler::{EntityEventHandler, EventHandler};
use kameo_es::Event;
use kameo_es::EventType;
use sqlx::{Postgres, Transaction};

/// Idempotent audit projector for the `BlockMembership` aggregate (v1 scope).
#[derive(Clone, Default, Debug)]
pub struct AuditProjector;

impl<'a> EventHandler<Transaction<'a, Postgres>> for AuditProjector {
    type Error = sqlx::Error;
}

impl<'a> EntityEventHandler<BlockMembership, Transaction<'a, Postgres>> for AuditProjector {
    async fn handle(
        &mut self,
        ctx: &mut Transaction<'a, Postgres>,
        _id: uuid::Uuid,
        event: Event<MembershipEvent, MembershipMetadata>,
    ) -> Result<(), Self::Error> {
        let block_id = match &event.data {
            MembershipEvent::MemberInvited { block_id, .. }
            | MembershipEvent::InvitationAccepted { block_id, .. }
            | MembershipEvent::RoleGranted { block_id, .. }
            | MembershipEvent::MemberRemoved { block_id, .. }
            | MembershipEvent::OwnerBootstrapped { block_id, .. } => block_id.0,
        };
        let event_type = event.data.event_type().to_string();
        let actor: Option<String> = event
            .metadata
            .data
            .as_ref()
            .and_then(|m| m.actor.clone())
            .map(|u| u.as_str().to_string());
        let payload = serde_json::to_value(&event.data).expect("MembershipEvent serializes");

        // Deterministic content key: identical for a redelivered event, so
        // `ON CONFLICT (event_key) DO NOTHING` dedupes redeliveries even though
        // SierraDB assigns a fresh `event.id` on every append.
        let event_key = format!("membership:{block_id}:{event_type}:{payload}");

        sqlx::query(
            r#"
            INSERT INTO projection_audit
                (id, event_key, entity_type, entity_id, event_type, block_id, series_id, actor, payload, occurred_at)
            VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
            ON CONFLICT (event_key) DO NOTHING
            "#,
        )
        .bind(event.id)
        .bind(event_key)
        .bind("membership")
        .bind(block_id.to_string())
        .bind(event_type)
        .bind(block_id)
        .bind(Option::<uuid::Uuid>::None)
        .bind(actor)
        .bind(payload)
        .bind(event.timestamp)
        .execute(&mut **ctx)
        .await?;

        Ok(())
    }
}
