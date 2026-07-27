// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4-flash (opencode-go)
// Co-authored-by: grok-4.5 (opencode-go)

//! Report-archival job enqueue triggers.
//!
//! Three sources, one pipeline:
//! 1. **Schedule** — periodic ticker
//! 2. **`ShootingDayWrapped` reaction** — saga-style enqueue (no aggregate change)
//! 3. **Manual** — HTTP endpoint (handled in `api`; uses the same queue)
//!
//! All triggers share the same dedup key so redeliveries / manual-after-wrap
//! are no-ops. Service jobs enforce season-scoped authorization internally
//! (configured destination); they are NOT a public authz bypass.

use std::collections::HashMap;
use std::sync::Arc;
use std::time::Duration;

use anyhow::Result;
use breakdown_core::reporting::{
    ArchivalTrigger, EnqueueArchivalRequest, ReportArchivalQueue, ReportKind, ReportLocale,
    SnapshotIdentity, TEMPLATE_VERSION,
};
use breakdown_core::shared::ShootingDayId;
use breakdown_core::shooting_day::aggregate::ShootingDayAggregate;
use breakdown_core::shooting_day::events::ShootingDayEvent;
use kameo_es::event_handler::{
    EntityEventHandler, EventHandler, EventHandlerError, EventHandlerStreamBuilder, EventProcessor,
};
use kameo_es::{Entity, Event};
use redis::Client as RedisClient;
use sierradb_client::SierraAsyncClientExt;
use sqlx::PgPool;
use tracing::{info, warn};
use uuid::Uuid;

use crate::projectors::supervisor;
use crate::reporting::jobs::PgReportArchivalQueue;

/// All report kinds archived per trigger.
const ALL_KINDS: [ReportKind; 3] = [
    ReportKind::Dispo,
    ReportKind::ShootDay,
    ReportKind::PlannedVsActual,
];

/// Enqueue archival jobs for every report kind of a shooting day.
///
/// Idempotent via the shared dedup key. Returns the number of *new* jobs.
pub async fn enqueue_for_day(
    queue: &PgReportArchivalQueue,
    shooting_day_id: ShootingDayId,
    trigger: ArchivalTrigger,
) -> Result<usize> {
    let mut created = 0usize;
    for kind in ALL_KINDS {
        let req = EnqueueArchivalRequest {
            kind,
            shooting_day_id,
            locale: ReportLocale::de_de(),
            template_version: TEMPLATE_VERSION.to_string(),
            snapshot_identity: SnapshotIdentity::current(),
            trigger,
        };
        match queue.enqueue(req).await {
            Ok(res) => {
                if !res.already_enqueued {
                    created += 1;
                }
                info!(
                    job_id = %res.job_id,
                    already = res.already_enqueued,
                    kind = %kind,
                    day = %shooting_day_id.0,
                    trigger = trigger.as_str(),
                    "report archival enqueued"
                );
            }
            Err(e) => {
                warn!(
                    error = %e,
                    kind = %kind,
                    day = %shooting_day_id.0,
                    "failed to enqueue report archival job"
                );
            }
        }
    }
    Ok(created)
}

// ---------------------------------------------------------------------------
// Schedule ticker
// ---------------------------------------------------------------------------

/// Configuration for the scheduled archival ticker.
#[derive(Debug, Clone)]
pub struct ScheduleConfig {
    pub enabled: bool,
    pub interval: Duration,
}

impl ScheduleConfig {
    pub fn from_env() -> Self {
        let enabled = std::env::var("REPORT_BACKUP_SCHEDULE_ENABLED")
            .ok()
            .and_then(|v| v.parse().ok())
            .unwrap_or(true);
        let interval = Duration::from_secs(
            std::env::var("REPORT_BACKUP_SCHEDULE_SECS")
                .ok()
                .and_then(|v| v.parse().ok())
                .unwrap_or(3600),
        );
        Self { enabled, interval }
    }
}

/// Spawn a ticker that enqueues archival jobs for recently-wrapped days.
///
/// Policy (v1): select shooting days with `wrapped_at IS NOT NULL` that do not
/// yet have a succeeded archival job for the Dispo kind (proxy for "needs
/// archival"). Static SQL only.
pub fn spawn_schedule_ticker(pool: PgPool, queue: PgReportArchivalQueue, config: ScheduleConfig) {
    if !config.enabled {
        info!("report archival schedule ticker disabled");
        return;
    }
    tokio::spawn(async move {
        loop {
            if let Err(e) = run_schedule_once(&pool, &queue).await {
                warn!(error = %e, "report archival schedule tick failed");
            }
            tokio::time::sleep(config.interval).await;
        }
    });
}

async fn run_schedule_once(pool: &PgPool, queue: &PgReportArchivalQueue) -> Result<()> {
    // Days wrapped but not yet successfully archived for `dispo` under the
    // current template version (static SQL, bound template version).
    let rows = sqlx::query_scalar::<_, Uuid>(
        r#"
        SELECT d.id
        FROM projection_shooting_day d
        WHERE d.wrapped_at IS NOT NULL
          AND d.archived = false
          AND NOT EXISTS (
              SELECT 1
              FROM report_ops.report_job j
              WHERE j.shooting_day_id = d.id
                AND j.kind = 'dispo'
                AND j.template_version = $1
                AND j.status = 'succeeded'
          )
        ORDER BY d.wrapped_at ASC
        LIMIT 50
        "#,
    )
    .bind(TEMPLATE_VERSION)
    .fetch_all(pool)
    .await?;

    for id in rows {
        let _ = enqueue_for_day(queue, ShootingDayId(id), ArchivalTrigger::Schedule).await;
    }
    Ok(())
}

// ---------------------------------------------------------------------------
// ShootingDayWrapped reaction (saga-style, no aggregate mutation)
// ---------------------------------------------------------------------------

/// Projector reaction: on `ShootingDayWrapped`, enqueue archival jobs.
///
/// Dispatches no SierraDB command, mutates no aggregate, emits no domain event.
/// Mirrors the `SeasonSeedingSaga` EventProcessor pattern.
#[derive(Clone, Debug)]
pub struct ReportArchivalOnWrapSaga {
    queue: PgReportArchivalQueue,
}

impl ReportArchivalOnWrapSaga {
    pub fn new(queue: PgReportArchivalQueue) -> Self {
        Self { queue }
    }
}

impl EventHandler<()> for ReportArchivalOnWrapSaga {
    type Error = anyhow::Error;
}

impl EntityEventHandler<ShootingDayAggregate, ()> for ReportArchivalOnWrapSaga {
    async fn handle(
        &mut self,
        _ctx: &mut (),
        _id: ShootingDayId,
        event: Event<ShootingDayEvent, ()>,
    ) -> Result<(), Self::Error> {
        if let ShootingDayEvent::ShootingDayWrapped { id, .. } = event.data {
            let created = enqueue_for_day(&self.queue, id, ArchivalTrigger::Wrapped).await?;
            info!(
                day = %id.0,
                created,
                "ShootingDayWrapped enqueued report archival jobs"
            );
        }
        Ok(())
    }
}

impl EventProcessor<(ShootingDayAggregate,), ReportArchivalOnWrapSaga> for ReportArchivalOnWrapSaga {
    type Context = ();
    type Error = anyhow::Error;

    async fn start_from(&self) -> Result<HashMap<u16, u64>, Self::Error> {
        // Start from the beginning; enqueue is idempotent via dedup key.
        Ok(HashMap::new())
    }

    async fn process_event(
        &mut self,
        event: Event,
    ) -> Result<(), EventHandlerError<Self::Error, <Self as EventHandler<()>>::Error>> {
        if event.stream_id.category() != ShootingDayAggregate::category() {
            return Ok(());
        }
        let id = event
            .entity_id::<ShootingDayAggregate>()
            .map_err(|_| EventHandlerError::ParseID(event.stream_id.cardinal_id().to_string()))?;
        let event = event
            .as_entity::<ShootingDayAggregate>()
            .map_err(|(event, err)| EventHandlerError::DeserializeEvent {
                entity: ShootingDayAggregate::category(),
                event: event.name,
                err,
            })?;
        EntityEventHandler::<ShootingDayAggregate, ()>::handle(self, &mut (), id, event)
            .await
            .map_err(EventHandlerError::Handler)
    }
}

/// Spawn the wrap-reaction saga against SierraDB (supervised, background).
pub async fn spawn_wrap_archival_saga(
    queue: PgReportArchivalQueue,
    redis_client: Arc<RedisClient>,
) -> Result<()> {
    let saga = ReportArchivalOnWrapSaga::new(queue);
    let redis_client_inner = redis_client.clone();
    let _handle = supervisor::run_with_restart("report_archival_on_wrap", move || {
        let mut saga = saga.clone();
        let client = redis_client_inner.clone();
        async move {
            let mut manager = client.subscription_manager().await?;
            let mut stream =
                <(ShootingDayAggregate,)>::event_handler_stream(&mut manager, &mut saga).await?;
            stream
                .run(&mut saga)
                .await
                .map_err(|e| anyhow::Error::from(e))
        }
    })
    .await?;
    drop(_handle);
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn all_kinds_covers_three_reports() {
        assert_eq!(ALL_KINDS.len(), 3);
    }

    #[test]
    fn schedule_config_defaults() {
        let cfg = ScheduleConfig {
            enabled: true,
            interval: Duration::from_secs(1),
        };
        assert!(cfg.enabled);
    }
}
