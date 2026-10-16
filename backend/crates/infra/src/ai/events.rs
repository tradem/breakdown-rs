// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3 (neuralwatt)

//! In-process job event fan-out and its PostgreSQL bridge (issue #664).
//!
//! Hexagonal seam (ADR-038 D4): every SSE client subscribes through the
//! storage-agnostic [`AiImportQueue::subscribe`](breakdown_core::ai::AiImportQueue::subscribe)
//! port, which here is backed by an in-process [`tokio::sync::broadcast`]
//! hub. Publication is two-layered:
//!
//! * **In-process** (`hub.notify(id)`): called by queue adapters directly
//!   after their write commits — works for PostgreSQL, in-memory test
//!   fakes, and a future SQLite operating mode without `LISTEN/NOTIFY`.
//! * **Cross-instance** (PostgreSQL mode only): fenced lifecycle/progress
//!   SQL statements carry `pg_notify('ai_import_job_events', id::text)`,
//!   and ONE shared background `PgListener` task per API instance forwards
//!   the payload into the local hub. One listening connection per node,
//!   never one per SSE client.
//!
//! Receivers treat a broadcast lag (`RecvError::Lagged`) as a synthetic
//! wake-up: because every consumer re-reads the authoritative job row via
//! the queue instead of trusting the notification payload, a lagged client
//! converges on the latest state rather than missing it.

use std::pin::Pin;
use std::time::Duration;

use futures::Stream;
use tokio::sync::broadcast;
use tracing::{info, warn};

use breakdown_core::ai::AiImportJobId;

#[cfg(test)]
#[path = "events_tests.rs"]
mod events_tests;

/// PostgreSQL `NOTIFY` channel carrying job ids after fenced writes.
pub const JOB_EVENTS_CHANNEL: &str = "ai_import_job_events";

/// Broadcast capacity per job-event hub. A burst larger than this makes slow
/// SSE receivers lag — which is a synthetic wake-up, never a lost terminal
/// state, because the handler always re-reads the row.
const EVENT_HUB_CAPACITY: usize = 256;

/// Bounded reconnect backoff of the shared `PgListener` task. Linear, small:
/// a transient listener outage only delays push latency, and correctness
/// never depends on it (the SSE handler re-reads on every wake-up and the
/// first snapshot is always fresh).
const PG_LISTENER_RECONNECT_BACKOFF: Duration = Duration::from_secs(2);
const PG_LISTENER_RECONNECT_ATTEMPTS: u32 = 5;

/// In-process fan-out of AI import job wake-ups (issue #664).
///
/// Clonable handle around one `broadcast::Sender<AiImportJobId>`.
/// `notify` is non-blocking and infallible: with zero listeners the send is
/// a no-op, and a listener that fell behind merely lags (a wake-up, not a
/// loss — see the module docs).
#[derive(Clone)]
pub struct AiJobEventHub {
    tx: broadcast::Sender<AiImportJobId>,
}

impl std::fmt::Debug for AiJobEventHub {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("AiJobEventHub")
            .field("receivers", &self.tx.receiver_count())
            .finish()
    }
}

impl Default for AiJobEventHub {
    fn default() -> Self {
        Self::new()
    }
}

impl AiJobEventHub {
    pub fn new() -> Self {
        let (tx, _) = broadcast::channel(EVENT_HUB_CAPACITY);
        Self { tx }
    }

    /// Publish a job wake-up. Deliberately ignores the send result: `Err`
    /// means "no live receiver", which is the normal case when nobody is
    /// watching a job — never an error worth surfacing (reliability rule
    /// #165 is about *fallible* results; this send cannot fail in a way a
    /// caller could act on).
    pub fn notify(&self, id: AiImportJobId) {
        // An `Err` means "no live receiver" — the normal case when nobody is
        // watching a job, not a failure a caller could act on. Matched
        // explicitly (never `let _ =`, discard-result rule) and left quiet:
        // workers publish progress even when nobody is subscribed.
        if self.tx.send(id).is_err() {
            // No active subscriber; nothing to deliver.
        }
    }

    /// Subscribe to wake-ups for `id`. Yields the job id on every matching
    /// notification and on receiver lag (synthetic wake-up). Ends when the
    /// hub's last sender clone is dropped.
    pub fn subscribe(
        &self,
        id: AiImportJobId,
    ) -> Pin<Box<dyn Stream<Item = AiImportJobId> + Send>> {
        let rx = self.tx.subscribe();
        Box::pin(futures::stream::unfold(rx, move |mut rx| async move {
            loop {
                match rx.recv().await {
                    Ok(received) if received == id => return Some((id, rx)),
                    // Another job's notification — this stream is per-job.
                    Ok(_) => continue,
                    // Fell behind the burst: the handler re-reads the row on
                    // any wake-up, so treat lag as a wake-up, not a miss.
                    Err(broadcast::error::RecvError::Lagged(_)) => return Some((id, rx)),
                    // Hub dropped: end the stream so the SSE loop can close.
                    Err(broadcast::error::RecvError::Closed) => return None,
                }
            }
        }))
    }
}

/// Spawn the shared PostgreSQL `LISTEN` bridge for one API instance (issue
/// #664, ADR-038 D4).
///
/// One background task per process holds the single listening connection on
/// [`JOB_EVENTS_CHANNEL`]; every notification's UUID payload is parsed and
/// forwarded to the local [`AiJobEventHub`]. Transient connection drops are
/// reconnected with a small bounded linear backoff and logged as warnings —
/// push delivery may lag, but correctness never depends on the bridge
/// (snapshot-first SSE + re-read on wake-up).
///
/// The task ends when `shutdown` flips or the pool is closed; the returned
/// handle should be kept alive and joined during graceful shutdown.
pub fn spawn_pg_job_event_listener(
    pool: sqlx::PgPool,
    hub: AiJobEventHub,
    shutdown: crate::ai::worker_loop::ShutdownSignal,
) -> tokio::task::JoinHandle<()> {
    tokio::spawn(async move {
        let mut shutdown = shutdown;
        loop {
            if *shutdown.borrow() {
                info!("AI import job event listener shutting down");
                return;
            }

            match sqlx::postgres::PgListener::connect_with(&pool).await {
                Ok(mut listener) => {
                    if let Err(error) = listener.listen(JOB_EVENTS_CHANNEL).await {
                        warn!(%error, "failed to subscribe the AI import job event listener; retrying");
                        tokio::select! {
                            _ = shutdown.changed() => return,
                            _ = tokio::time::sleep(PG_LISTENER_RECONNECT_BACKOFF) => {}
                        }
                        continue;
                    }
                    info!(
                        channel = JOB_EVENTS_CHANNEL,
                        "AI import job event listener connected"
                    );
                    loop {
                        tokio::select! {
                            _ = shutdown.changed() => {
                                info!("AI import job event listener shutting down");
                                return;
                            }
                            notification = listener.recv() => {
                                match notification {
                                    Ok(notification) => {
                                        // The payload is the job id written by the
                                        // fenced SQL statements; a malformed payload
                                        // is logged and skipped, never fatal.
                                        match parse_job_id(notification.payload()) {
                                            Some(id) => hub.notify(id),
                                            None => warn!(
                                                channel = JOB_EVENTS_CHANNEL,
                                                payload = notification.payload(),
                                                "ignoring malformed AI import job event payload"
                                            ),
                                        }
                                    }
                                    Err(error) => {
                                        warn!(%error, "AI import job event listener dropped; reconnecting");
                                        break;
                                    }
                                }
                            }
                        }
                    }
                }
                Err(error) => {
                    warn!(%error, "failed to connect the AI import job event listener; retrying");
                }
            }

            // Bounded linear backoff before the next reconnect attempt.
            for attempt in 0..PG_LISTENER_RECONNECT_ATTEMPTS {
                if *shutdown.borrow() {
                    return;
                }
                tokio::select! {
                    _ = shutdown.changed() => return,
                    _ = tokio::time::sleep(PG_LISTENER_RECONNECT_BACKOFF * (attempt + 1)) => {}
                }
            }
        }
    })
}

/// Parse one `pg_notify` payload into a job id. The payload is always the
/// job's UUID, written by the fenced SQL statements; a malformed payload is
/// a log-and-skip, never fatal.
fn parse_job_id(value: &str) -> Option<AiImportJobId> {
    uuid::Uuid::parse_str(value)
        .map(AiImportJobId::from_uuid)
        .ok()
}
