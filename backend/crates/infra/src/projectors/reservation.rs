// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3 (neuralwatt)
// Co-authored-by: glm-5.3-flash (opencode-go)

//! Projector for the synthetic `reservation` category (ADR-036, issue #586).
//!
//! Mirrors the claim lifecycle of the reservation streams into
//! `projection_number_reservation` — observability and reaper candidate
//! selection only. The event store holds the authoritative claim state; this
//! table never gates a write path (reaper acts only after re-reading the
//! event store), which is why there is no `invariant_skip` interaction here:
//! reservation rows carry no unique constraint beyond the primary key.

use crate::reservations::event::{ReservationEntity, ReservationEvent, ReservationKind};
use breakdown_core::shared::EventMetadata;
use kameo_es::Event;
use kameo_es::event_handler::{EntityEventHandler, EventHandler};
use sqlx::{Acquire, Postgres, Transaction};

use super::PROJECTOR_VERSION;

/// Idempotent projector for the synthetic `ReservationEntity`.
#[derive(Clone, Default, Debug)]
pub struct ReservationProjector;

impl<'a> EventHandler<Transaction<'a, Postgres>> for ReservationProjector {
    type Error = sqlx::Error;
}

impl<'a> EntityEventHandler<ReservationEntity, Transaction<'a, Postgres>> for ReservationProjector {
    async fn handle(
        &mut self,
        ctx: &mut Transaction<'a, Postgres>,
        id: String,
        event: Event<ReservationEvent, EventMetadata>,
    ) -> Result<(), Self::Error> {
        // `_id` (the stream cardinal id) duplicates the key; use the key from
        // the stream id minus the category prefix for one canonical shape.
        let _ = id;

        match event.data {
            ReservationEvent::Reserved { aggregate_id } => {
                let key = stream_key(&event);
                let kind = ReservationKind::from_key(&key).map_or_else(
                    || {
                        tracing::warn!(
                            stream_id = %event.stream_id,
                            "reservation event on an unparsable key prefix — row skipped"
                        );
                        None
                    },
                    Some,
                );
                let Some(kind) = kind else {
                    return Ok(());
                };
                let mut sp = (&mut *ctx).begin().await?;
                sqlx::query(
                    r#"
                    INSERT INTO projection_number_reservation
                        (reservation_key, kind, aggregate_id, state, reserved_at, released_at,
                         stream_version, projector_version, updated_at)
                    VALUES ($1, $2, $3, 'reserved', $4, NULL, $5, $6, $7)
                    ON CONFLICT (reservation_key) DO UPDATE SET
                        kind = EXCLUDED.kind,
                        aggregate_id = EXCLUDED.aggregate_id,
                        state = 'reserved',
                        reserved_at = EXCLUDED.reserved_at,
                        released_at = NULL,
                        projector_version = EXCLUDED.projector_version,
                        updated_at = EXCLUDED.updated_at,
                        stream_version = EXCLUDED.stream_version
                    -- Redelivery idempotency: never regress the version.
                    WHERE projection_number_reservation.stream_version < EXCLUDED.stream_version
                    "#,
                )
                .bind(key)
                .bind(kind.as_str())
                .bind(aggregate_id)
                .bind(event.timestamp)
                .bind(event.stream_version as i64)
                .bind(PROJECTOR_VERSION)
                .bind(event.timestamp)
                .execute(&mut *sp)
                .await?;
                sp.commit().await?;
            }
            ReservationEvent::Released { aggregate_id } => {
                let key = stream_key(&event);
                // Version guard keeps redelivery idempotent.
                sqlx::query(
                    r#"
                    UPDATE projection_number_reservation
                    SET state = 'released',
                        released_at = $2,
                        aggregate_id = $3,
                        stream_version = $4,
                        projector_version = $5,
                        updated_at = $2
                    WHERE reservation_key = $1
                        AND stream_version < $4
                    "#,
                )
                .bind(key)
                .bind(event.timestamp)
                .bind(aggregate_id)
                .bind(event.stream_version as i64)
                .bind(PROJECTOR_VERSION)
                .execute(&mut **ctx)
                .await?;
            }
            ReservationEvent::Consumed { aggregate_id } => {
                let key = stream_key(&event);
                sqlx::query(
                    r#"
                    UPDATE projection_number_reservation
                    SET state = 'consumed',
                        aggregate_id = $2,
                        stream_version = $3,
                        projector_version = $4,
                        updated_at = $5
                    WHERE reservation_key = $1
                        AND stream_version < $3
                    "#,
                )
                .bind(key)
                .bind(aggregate_id)
                .bind(event.stream_version as i64)
                .bind(PROJECTOR_VERSION)
                .bind(event.timestamp)
                .execute(&mut **ctx)
                .await?;
            }
        }

        Ok(())
    }
}

/// Extracts the opaque key from a reservation event's stream id
/// (`reservation-<key>` → `<key>`).
fn stream_key(event: &Event<ReservationEvent, EventMetadata>) -> String {
    let full: &str = &event.stream_id;
    full.strip_prefix(crate::reservations::event::RESERVATION_STREAM_PREFIX)
        .unwrap_or(full)
        .to_owned()
}
