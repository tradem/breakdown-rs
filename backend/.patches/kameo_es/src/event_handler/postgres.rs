// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: Omen Alpha (pi)

use std::{
    collections::{hash_map::Entry, HashMap},
    fmt,
    marker::PhantomData,
    ops::ControlFlow,
    sync::Arc,
    time::{Duration, Instant},
};

use backon::{ExponentialBuilder, RetryableWithContext};
use futures::future::OptionFuture;
use kameo::{mailbox::Signal, prelude::*};
use redis::aio::MultiplexedConnection;
use sierradb_client::AsyncTypedCommands;
use sqlx::{AssertSqlSafe, PgPool, Postgres};
use thiserror::Error;
use tracing::{debug, error, info};

use crate::event_handler::EventErrorClassify;
use crate::Event;

use super::{CompositeEventHandler, EventHandler, EventHandlerError, EventProcessor};

pub struct PostgresProcessor<E, H>
where
    E: 'static,
    H: EventHandler<sqlx::Transaction<'static, Postgres>>
        + CompositeEventHandler<E, sqlx::Transaction<'static, Postgres>, PostgresEventProcessorError>
        + Send
        + 'static,
    <H as EventHandler<sqlx::Transaction<'static, Postgres>>>::Error:
        fmt::Debug + Sync + crate::event_handler::EventErrorClassify,
{
    pool: PgPool,
    conn: MultiplexedConnection,
    checkpoints_table: Arc<str>,
    dead_letter_table: Arc<str>,
    projection_id: Arc<str>,
    handler: H,
    worker_count: u16,
    workers: HashMap<u16, ActorRef<Worker<E, H>>>,
    last_flushed_sequences: HashMap<u16, u64>,
    flush_live_interval_time: Duration,
    flush_live_interval_events: u64,
    flush_replay_interval_time: Duration,
    flush_replay_interval_events: u64,
}

impl<E, H> PostgresProcessor<E, H>
where
    E: 'static,
    H: EventHandler<sqlx::Transaction<'static, Postgres>>
        + CompositeEventHandler<E, sqlx::Transaction<'static, Postgres>, PostgresEventProcessorError>
        + Send
        + 'static,
    <H as EventHandler<sqlx::Transaction<'static, Postgres>>>::Error:
        fmt::Debug + Sync + crate::event_handler::EventErrorClassify,
{
    pub async fn new(
        pool: PgPool,
        conn: MultiplexedConnection,
        checkpoints_table: impl Into<Arc<str>>,
        projection_id: impl Into<Arc<str>>,
        handler: H,
    ) -> sqlx::Result<Self> {
        let checkpoints_table = checkpoints_table.into();
        let projection_id = projection_id.into();

        // SMALLINT (INT2) column: decode as i16 — i32 fails on the second
        // startup as soon as at least one checkpoint row exists (issue #392).
        let partition_id_sequences: Vec<(i16, i64)> = sqlx::query_as(AssertSqlSafe(format!(
            "SELECT partition_id, sequence FROM {checkpoints_table} WHERE projection_id = $1",
        )))
        .bind(projection_id.as_ref())
        .fetch_all(&pool)
        .await?;

        for (partition_id, sequence) in &partition_id_sequences {
            info!(gauge.projection_sequence = sequence, %projection_id, partition_id, database = "postgres");
        }

        // Propagate decode failures instead of panicking in a production
        // startup path (repo no-panic rule, AGENTS.md §3).
        let last_flushed_sequences = partition_id_sequences
            .into_iter()
            .map(|(partition_id, sequence)| {
                let partition_id =
                    u16::try_from(partition_id).map_err(|err| sqlx::Error::ColumnDecode {
                        index: "partition_id".to_string(),
                        source: Box::new(err),
                    })?;
                let sequence =
                    u64::try_from(sequence).map_err(|err| sqlx::Error::ColumnDecode {
                        index: "sequence".to_string(),
                        source: Box::new(err),
                    })?;
                Ok((partition_id, sequence))
            })
            .collect::<sqlx::Result<HashMap<_, _>>>()?;

        Ok(PostgresProcessor {
            pool,
            conn,
            checkpoints_table: checkpoints_table.clone(),
            dead_letter_table: Arc::from("projection_dead_letter"),
            projection_id: projection_id.clone(),
            handler,
            worker_count: 16,
            workers: HashMap::new(),
            last_flushed_sequences,
            flush_live_interval_time: Duration::from_secs(2),
            flush_live_interval_events: 10,
            flush_replay_interval_time: Duration::from_secs(10),
            flush_replay_interval_events: 10_000,
        })
    }

    /// Number of parallelism.
    pub fn workers(mut self, count: u16) -> Self {
        self.worker_count = count;
        self
    }

    /// Override the dead-letter table used by the poison-event path
    /// (issue #37). Defaults to `projection_dead_letter`.
    pub fn dead_letter_table(mut self, table: impl Into<Arc<str>>) -> Self {
        self.dead_letter_table = table.into();
        self
    }

    /// The number of seconds since last flush before attempting to flush again.
    pub fn flush_live_interval_time(mut self, period: Duration) -> Self {
        self.flush_live_interval_time = period;
        self
    }

    /// The number of events since the last flush before attempting to flush again when in live mode.
    pub fn flush_live_interval_events(mut self, events_count: u64) -> Self {
        self.flush_live_interval_events = events_count;
        self
    }

    /// The number of seconds since last flush before attempting to flush again.
    pub fn flush_replay_interval_time(mut self, period: Duration) -> Self {
        self.flush_replay_interval_time = period;
        self
    }

    /// The number of events since the last flush before attempting to flush again when in replay mode.
    pub fn flush_replay_interval_events(mut self, events_count: u64) -> Self {
        self.flush_replay_interval_events = events_count;
        self
    }

    /// Gets a reference to the inner handler.
    pub fn handler(&mut self) -> &mut H {
        &mut self.handler
    }
}

impl<E, H> EventProcessor<E, H> for ActorRef<PostgresProcessor<E, H>>
where
    E: 'static,
    H: EventHandler<sqlx::Transaction<'static, Postgres>>
        + CompositeEventHandler<E, sqlx::Transaction<'static, Postgres>, PostgresEventProcessorError>
        + Clone
        + Send
        + 'static,
    for<'a> <H as EventHandler<sqlx::Transaction<'a, Postgres>>>::Error:
        fmt::Debug + Unpin + Sync + crate::event_handler::EventErrorClassify + 'static,
{
    type Context = sqlx::Transaction<'static, Postgres>;
    type Error = PostgresEventProcessorError;

    async fn start_from(&self) -> Result<HashMap<u16, u64>, Self::Error> {
        let from_map = self
            .ask(GetStartFrom)
            .send()
            .await
            .map_err(|err| err.map_msg(|_| ()))?;
        Ok(from_map)
    }

    async fn process_event(
        &mut self,
        event: Event,
    ) -> Result<(), EventHandlerError<Self::Error, <H as EventHandler<Self::Context>>::Error>> {
        self.tell(HandleEvent(event)).send().await.unwrap();
        Ok(())
    }

    async fn dead_letter_undecodable(
        &mut self,
        raw_event: sierradb_client::Event,
        err: crate::TryFromSierraEventError,
    ) -> Result<(), Self::Error> {
        self.ask(DeadLetterUndecodable {
            event: raw_event,
            err,
        })
        .send()
        .await
        .map_err(|send_err| match send_err.map_msg(|_| ()) {
            // The actor's handler error is authoritative (DLQ write etc.).
            SendError::HandlerError(processor_err) => processor_err,
            // Actor not running/stopped/mailbox full/timeout — an
            // infrastructure failure surfaced as an IO error so the epoch
            // restart (transient behavior) kicks in.
            other => PostgresEventProcessorError::Postgres(sqlx::Error::Io(std::io::Error::other(
                other.to_string(),
            ))),
        })?;
        Ok(())
    }
}

impl<E, H> Actor for PostgresProcessor<E, H>
where
    E: 'static,
    H: EventHandler<sqlx::Transaction<'static, Postgres>>
        + CompositeEventHandler<E, sqlx::Transaction<'static, Postgres>, PostgresEventProcessorError>
        + Send
        + 'static,
    <H as EventHandler<sqlx::Transaction<'static, Postgres>>>::Error:
        fmt::Debug + Sync + crate::event_handler::EventErrorClassify,
{
    type Args = Self;
    type Error = anyhow::Error;

    async fn on_start(args: Self::Args, _actor_ref: ActorRef<Self>) -> Result<Self, Self::Error> {
        Ok(args)
    }

    async fn on_link_died(
        &mut self,
        _actor_ref: WeakActorRef<Self>,
        id: ActorId,
        reason: ActorStopReason,
    ) -> Result<ControlFlow<ActorStopReason>, Self::Error> {
        match &reason {
            ActorStopReason::Normal => {
                info!("partition worker died normally");
                self.workers.retain(|_, worker| worker.id() != id);
                Ok(ControlFlow::Continue(()))
            }
            _ => {
                error!("partition worker died abnormally - stopping coordinator");
                Ok(ControlFlow::Break(ActorStopReason::LinkDied {
                    id,
                    reason: Box::new(reason),
                }))
            }
        }
    }
}

struct GetStartFrom;

impl<E, H> Message<GetStartFrom> for PostgresProcessor<E, H>
where
    E: 'static,
    H: EventHandler<sqlx::Transaction<'static, Postgres>>
        + CompositeEventHandler<E, sqlx::Transaction<'static, Postgres>, PostgresEventProcessorError>
        + Send
        + 'static,
    <H as EventHandler<sqlx::Transaction<'static, Postgres>>>::Error:
        fmt::Debug + Sync + crate::event_handler::EventErrorClassify,
{
    type Reply = Result<HashMap<u16, u64>, sqlx::Error>;

    async fn handle(
        &mut self,
        _msg: GetStartFrom,
        _ctx: &mut Context<Self, Self::Reply>,
    ) -> Self::Reply {
        Ok(self
            .last_flushed_sequences
            .iter()
            .map(|(partition_id, sequence)| (*partition_id, sequence + 1))
            .collect())
    }
}

/// Dead-letter an undecodable Sierra message (issue #411): the actor
/// records the raw message durably and advances the checkpoint past it in
/// one transaction.
struct DeadLetterUndecodable {
    event: sierradb_client::Event,
    err: crate::TryFromSierraEventError,
}

impl<E, H> Message<DeadLetterUndecodable> for PostgresProcessor<E, H>
where
    E: 'static,
    H: EventHandler<sqlx::Transaction<'static, Postgres>>
        + CompositeEventHandler<E, sqlx::Transaction<'static, Postgres>, PostgresEventProcessorError>
        + Send
        + 'static,
    <H as EventHandler<sqlx::Transaction<'static, Postgres>>>::Error:
        fmt::Debug + Sync + crate::event_handler::EventErrorClassify,
{
    type Reply = Result<(), PostgresEventProcessorError>;

    async fn handle(
        &mut self,
        DeadLetterUndecodable { event, err }: DeadLetterUndecodable,
        _ctx: &mut Context<Self, Self::Reply>,
    ) -> Self::Reply {
        let partition_id = event.partition_id;
        let sequence = event.partition_sequence;
        let smallint_partition = partition_id_to_smallint(partition_id)?;

        let mut tx = self.pool.begin().await?;

        sqlx::query(AssertSqlSafe(format!(
            "
            INSERT INTO {} (projection_id, partition_id, sequence, stream_id, event_name, sqlstate, constraint_name, error_message, attempts, first_seen_at, last_seen_at)
            VALUES ($1, $2, $3, $4, $5, NULL, NULL, $6, 1, now(), now())
            ON CONFLICT (projection_id, partition_id, sequence) DO UPDATE SET
                error_message = EXCLUDED.error_message,
                attempts = {}.attempts + 1,
                last_seen_at = now()
            ",
            self.dead_letter_table, self.dead_letter_table
        )))
        .bind(self.projection_id.as_ref())
        .bind(smallint_partition)
        .bind(sequence as i64)
        .bind(event.stream_id.clone())
        .bind(event.event_name.clone())
        .bind(err.to_string())
        .execute(&mut *tx)
        .await?;

        sqlx::query(AssertSqlSafe(format!(
            "
            INSERT INTO {} (projection_id, partition_id, sequence)
            VALUES ($1, $2, $3)
            ON CONFLICT (projection_id, partition_id) DO UPDATE SET
                sequence = GREATEST({}.sequence, EXCLUDED.sequence)
            ",
            self.checkpoints_table, self.checkpoints_table
        )))
        .bind(self.projection_id.as_ref())
        .bind(smallint_partition)
        .bind(sequence as i64)
        .execute(&mut *tx)
        .await?;

        tx.commit().await?;

        // Keep the in-memory map consistent so `GetStartFrom` (a new epoch's
        // subscription point) does not rewind to the dead-lettered message.
        self.last_flushed_sequences.insert(partition_id, sequence);

        error!(
            projection_id = %self.projection_id,
            partition_id,
            sequence,
            stream_id = %event.stream_id,
            event_name = %event.event_name,
            "dead-lettered undecodable Sierra message (issue #37/#411); checkpoint advanced past it, projector continues"
        );

        Ok(())
    }
}

struct HandleEvent(Event);

impl<E, H> Message<HandleEvent> for PostgresProcessor<E, H>
where
    E: 'static,
    H: EventHandler<sqlx::Transaction<'static, Postgres>>
        + CompositeEventHandler<E, sqlx::Transaction<'static, Postgres>, PostgresEventProcessorError>
        + Clone
        + Send
        + 'static,
    for<'a> <H as EventHandler<sqlx::Transaction<'a, Postgres>>>::Error:
        fmt::Debug + Unpin + Sync + crate::event_handler::EventErrorClassify + 'static,
{
    type Reply = ForwardedReply<
        HandleEvent,
        Result<
            (),
            EventHandlerError<
                PostgresEventProcessorError,
                <H as EventHandler<sqlx::Transaction<'static, Postgres>>>::Error,
            >,
        >,
    >;

    async fn handle(
        &mut self,
        HandleEvent(event): HandleEvent,
        ctx: &mut Context<Self, Self::Reply>,
    ) -> Self::Reply {
        let worker_id = event.partition_id % self.worker_count;
        let entry = self.workers.entry(worker_id);
        let worker_ref = match entry {
            Entry::Vacant(vacancy) => {
                let worker_ref = Worker::spawn_link_with_mailbox(
                    ctx.actor_ref(),
                    Worker {
                        pool: self.pool.clone(),
                        conn: self.conn.clone(),
                        checkpoints_table: self.checkpoints_table.clone(),
                        dead_letter_table: self.dead_letter_table.clone(),
                        projection_id: self.projection_id.clone(),
                        handler: self.handler.clone(),
                        transaction: None,
                        events_since_flush: 0,
                        last_flushed_sequences: self.last_flushed_sequences.clone(),
                        last_handled_sequences: self.last_flushed_sequences.clone(),
                        partition_latest_sequences: HashMap::new(),
                        last_flushed: Instant::now(),
                        flush_live_interval_time: self.flush_live_interval_time,
                        flush_live_interval_events: self.flush_live_interval_events,
                        flush_replay_interval_time: self.flush_replay_interval_time,
                        flush_replay_interval_events: self.flush_replay_interval_events,
                        is_live: false,
                        phantom: PhantomData,
                    },
                    mailbox::bounded(1024 * 4),
                )
                .await;

                vacancy.insert(worker_ref)
            }
            Entry::Occupied(occupied) => occupied.into_mut(),
        };

        ctx.forward(worker_ref, HandleEvent(event)).await
    }
}

struct Worker<E, H>
where
    E: 'static,
    H: EventHandler<sqlx::Transaction<'static, Postgres>>
        + CompositeEventHandler<E, sqlx::Transaction<'static, Postgres>, PostgresEventProcessorError>
        + Send
        + 'static,
    <H as EventHandler<sqlx::Transaction<'static, Postgres>>>::Error:
        fmt::Debug + Sync + crate::event_handler::EventErrorClassify,
{
    pool: PgPool,
    conn: MultiplexedConnection,
    checkpoints_table: Arc<str>,
    dead_letter_table: Arc<str>,
    projection_id: Arc<str>,
    handler: H,
    transaction: Option<sqlx::Transaction<'static, Postgres>>,
    events_since_flush: u64,
    last_flushed: Instant,
    last_flushed_sequences: HashMap<u16, u64>,
    last_handled_sequences: HashMap<u16, u64>,
    partition_latest_sequences: HashMap<u16, Option<u64>>,
    flush_live_interval_time: Duration,
    flush_live_interval_events: u64,
    flush_replay_interval_time: Duration,
    flush_replay_interval_events: u64,
    is_live: bool,
    phantom: PhantomData<fn() -> E>,
}

impl<E, H> Worker<E, H>
where
    E: 'static,
    H: EventHandler<sqlx::Transaction<'static, Postgres>>
        + CompositeEventHandler<E, sqlx::Transaction<'static, Postgres>, PostgresEventProcessorError>
        + Send
        + 'static,
    <H as EventHandler<sqlx::Transaction<'static, Postgres>>>::Error:
        fmt::Debug + Sync + crate::event_handler::EventErrorClassify,
{
    async fn handle_event(
        &mut self,
        event: Event,
    ) -> Result<
        (),
        EventHandlerError<
            PostgresEventProcessorError,
            <H as EventHandler<sqlx::Transaction<'static, Postgres>>>::Error,
        >,
    > {
        if self
            .last_handled_sequences
            .get(&event.partition_id)
            .map(|last_sequence| last_sequence >= &event.partition_sequence)
            .unwrap_or(false)
        {
            debug!(
                "ignoring already handled event {}:{}",
                event.partition_id, event.partition_sequence
            );
            return Ok(());
        }

        match self.partition_latest_sequences.entry(event.partition_id) {
            Entry::Occupied(_) => {}
            Entry::Vacant(entry) => {
                // We came across a partition we haven't handled, switch back to replaying
                self.is_live = false;

                let epseq = self.conn.epseq_by_id(event.partition_id).await?;
                entry.insert(epseq);
            }
        }

        let partition_id = event.partition_id;
        let sequence = event.partition_sequence;

        let result = handle_event
            .retry(ExponentialBuilder::new().with_jitter().with_max_times(5))
            .context((&self.pool, &mut self.transaction, &mut self.handler, &event))
            .notify(|err, _dur| {
                error!("failed to process event: {err:?}");
            })
            .await
            .1;

        // Issue #37: a *permanent* error (constraint violation, event
        // deserialization, ...) can never succeed on retry — retrying and
        // restart-looping would stall the projector forever. Dead-letter the
        // event and advance the checkpoint past it so the projector keeps
        // progressing. Transient errors keep the previous
        // propagate-and-restart behavior.
        //
        // The error is fully destructured *before* any `await` (into plain
        // `Send` data) — holding a generic `H::Error` across an await would
        // make the worker future non-`Send` for handlers whose error type is
        // only `Sync` for the `'static` instantiation.
        let poison = match result {
            Ok(()) => None,
            Err(err) if err.is_permanent_event_error() => {
                let (sqlstate, constraint) = match &err {
                    EventHandlerError::Handler(handler_err) => {
                        handler_err.permanent_error_details()
                    }
                    _ => (None, None),
                };
                // `EventHandlerError` only implements `Display` when its
                // payloads do; use `Debug` (always available here) for the
                // recorded message.
                let error_message = format!("{err:?}");
                Some((sqlstate, constraint, error_message))
            }
            Err(err) => return Err(err),
        };

        if let Some((sqlstate, constraint, error_message)) = poison {
            self.dead_letter_event(&event, sqlstate, constraint, error_message)
                .await?;
        }

        self.last_handled_sequences.insert(partition_id, sequence);
        self.events_since_flush += 1;

        let replaying = !self.is_live
            && self
                .partition_latest_sequences
                .iter()
                .any(|(partition_id, latest_sequence)| {
                    let gap = latest_sequence
                        .map(|latest_sequence| {
                            match self.last_handled_sequences.get(partition_id) {
                                Some(last_handled_sequence) => {
                                    latest_sequence.saturating_sub(*last_handled_sequence)
                                }
                                None => latest_sequence + 1,
                            }
                        })
                        .unwrap_or(0);
                    gap > 0
                });

        let flush_reason = if replaying {
            if sequence.is_multiple_of(100) {
                info!(
                    "{} replay progress: {:.1}% ({}/{})",
                    self.projection_id,
                    self.replay_progress_percent(),
                    self.last_handled_sequences.len(),
                    self.partition_latest_sequences.len()
                );
            }

            // Replay
            (self.events_since_flush >= self.flush_replay_interval_events)
                .then_some(FlushReason::ReplayEventsInterval)
        } else {
            if !self.is_live {
                self.is_live = true;

                info!(
                    "projection {} is now live at {partition_id}:{sequence} for worker",
                    self.projection_id
                );
            }

            // Live
            (self.events_since_flush >= self.flush_live_interval_events)
                .then_some(FlushReason::LiveEventsInterval)
        };

        if let Some(flush_reason) = flush_reason {
            flush_retry
                .retry(ExponentialBuilder::new())
                .context((self, flush_reason))
                .notify(|err, _dur| {
                    error!("failed to flush events: {err:?}");
                })
                .await
                .1?;
        }

        Ok(())
    }

    /// Record an unprocessable event durably (issue #37): upsert into the
    /// dead-letter table and advance the projector's checkpoint past the
    /// event — reusing the worker's retained batch transaction so the
    /// earlier successful events' effects, the dead-letter row, and the
    /// checkpoint advance commit **atomically** (issue #37 review: a
    /// checkpoint jump past unflushed successful events would lose their
    /// effects on replay). If no transaction is retained, a fresh one is
    /// begun. On any failure the error propagates and the epoch restarts
    /// (the pre-#37 behavior), so a broken dead-letter path degrades safely.
    ///
    /// Idempotent: a replay of the same `(projection_id, partition_id,
    /// sequence)` bumps `attempts` instead of duplicating the row.
    async fn dead_letter_event(
        &mut self,
        event: &Event,
        sqlstate: Option<String>,
        constraint: Option<String>,
        error_message: String,
    ) -> Result<
        (),
        EventHandlerError<
            PostgresEventProcessorError,
            <H as EventHandler<sqlx::Transaction<'static, Postgres>>>::Error,
        >,
    > {
        let partition_id = event.partition_id;
        let sequence = event.partition_sequence;
        let smallint_partition =
            partition_id_to_smallint(partition_id).map_err(EventHandlerError::Processor)?;

        let sqlstate_log = sqlstate.clone().unwrap_or_else(|| "-".to_string());
        let constraint_log = constraint.clone().unwrap_or_else(|| "-".to_string());

        // Reuse the retained batch transaction (contains the rolled-back
        // savepoint only — earlier successful events' effects are intact) so
        // their effects commit atomically with the dead-letter row and the
        // checkpoint advance. Fall back to a fresh transaction when none is
        // retained (e.g. the failing event started the batch).
        let mut tx = match self.transaction.take() {
            Some(tx) => tx,
            None => self
                .pool
                .begin()
                .await
                .map_err(|err| EventHandlerError::Processor(err.into()))?,
        };

        sqlx::query(AssertSqlSafe(format!(
            "
            INSERT INTO {} (projection_id, partition_id, sequence, stream_id, event_name, sqlstate, constraint_name, error_message, attempts, first_seen_at, last_seen_at)
            VALUES ($1, $2, $3, $4, $5, $6, $7, $8, 1, now(), now())
            ON CONFLICT (projection_id, partition_id, sequence) DO UPDATE SET
                sqlstate = EXCLUDED.sqlstate,
                constraint_name = EXCLUDED.constraint_name,
                error_message = EXCLUDED.error_message,
                attempts = {}.attempts + 1,
                last_seen_at = now()
            ",
            self.dead_letter_table, self.dead_letter_table
        )))
        .bind(self.projection_id.as_ref())
        .bind(smallint_partition)
        .bind(sequence as i64)
        .bind(event.stream_id.to_string())
        .bind(event.name.clone())
        .bind(sqlstate)
        .bind(constraint)
        .bind(error_message)
        .execute(&mut *tx)
        .await
        .map_err(|err| EventHandlerError::Processor(err.into()))?;

        sqlx::query(AssertSqlSafe(format!(
            "
            INSERT INTO {} (projection_id, partition_id, sequence)
            VALUES ($1, $2, $3)
            ON CONFLICT (projection_id, partition_id) DO UPDATE SET
                sequence = GREATEST({}.sequence, EXCLUDED.sequence)
            ",
            self.checkpoints_table, self.checkpoints_table
        )))
        .bind(self.projection_id.as_ref())
        .bind(smallint_partition)
        .bind(sequence as i64)
        .execute(&mut *tx)
        .await
        .map_err(|err| EventHandlerError::Processor(err.into()))?;

        tx.commit()
            .await
            .map_err(|err| EventHandlerError::Processor(err.into()))?;

        // Keep the in-memory handled/flushed maps consistent so subsequent
        // flushes skip this partition (both equal) and the subscription does
        // not rewind to the poison event. The whole batch transaction was
        // committed above, so the flush counter resets too.
        self.last_handled_sequences.insert(partition_id, sequence);
        self.last_flushed_sequences.insert(partition_id, sequence);
        self.events_since_flush = 0;
        self.last_flushed = Instant::now();

        error!(
            projection_id = %self.projection_id,
            partition_id,
            sequence,
            stream_id = %event.stream_id,
            event_name = %event.name,
            sqlstate = %sqlstate_log,
            constraint = %constraint_log,
            "dead-lettered unprocessable event (issue #37); checkpoint advanced past it, projector continues"
        );

        Ok(())
    }

    async fn flush_checkpoint(
        &mut self,
        reason: FlushReason,
    ) -> Result<
        (),
        EventHandlerError<
            PostgresEventProcessorError,
            <H as EventHandler<sqlx::Transaction<'static, Postgres>>>::Error,
        >,
    > {
        let Some(tx) = self.transaction.as_mut() else {
            self.last_flushed = Instant::now();
            return Ok(());
        };

        for (partition_id, last_handled_sequence) in &self.last_handled_sequences {
            let last_flushed_sequence = self.last_flushed_sequences.get(partition_id);
            match (last_flushed_sequence, last_handled_sequence) {
                (None, last_handled_sequence) => {
                    info!("flushing due to {reason:?}");

                    self.handler
                        .flush(tx)
                        .await
                        .map_err(EventHandlerError::Handler)?;

                    let res = sqlx::query(AssertSqlSafe(format!(
                        "INSERT INTO {} (projection_id, partition_id, sequence) VALUES ($1, $2, $3)",
                        self.checkpoints_table
                    )))
                    .bind(self.projection_id.as_ref())
                    .bind(
                        partition_id_to_smallint(*partition_id)
                            .map_err(EventHandlerError::Processor)?,
                    )
                    .bind(*last_handled_sequence as i64)
                    .execute(&mut **tx)
                    .await;

                    match res {
                        Ok(_) => {
                            info!(gauge.projection_sequence = last_handled_sequence, projection_id = %self.projection_id, partition_id, database = "postgres");
                        }
                        Err(sqlx::Error::Database(db_err))
                            if db_err.code().as_deref() == Some("23505") =>
                        {
                            // 23505 is the error code for unique violations (e.g., primary key conflicts)
                            return Err(EventHandlerError::Processor(
                                PostgresEventProcessorError::UnexpectedLastEventId {
                                    expected: None,
                                },
                            ));
                        }
                        Err(err) => return Err(err.into()),
                    }
                }
                (Some(last_flushed_sequence), last_handled_sequence)
                    if last_flushed_sequence != last_handled_sequence =>
                {
                    info!("flushing due to {reason:?}");

                    self.handler
                        .flush(tx)
                        .await
                        .map_err(EventHandlerError::Handler)?;

                    let res = sqlx::query(AssertSqlSafe(format!(
                        "
                        UPDATE {} SET sequence = $1
                        WHERE projection_id = $2 AND partition_id = $3
                    ",
                        self.checkpoints_table
                    )))
                    .bind(*last_handled_sequence as i64)
                    .bind(self.projection_id.as_ref())
                    .bind(
                        partition_id_to_smallint(*partition_id)
                            .map_err(EventHandlerError::Processor)?,
                    )
                    .execute(&mut **tx)
                    .await?;
                    if res.rows_affected() == 0 {
                        return Err(EventHandlerError::Processor(
                            PostgresEventProcessorError::UnexpectedLastEventId {
                                expected: Some(*last_handled_sequence),
                            },
                        ));
                    }

                    info!(gauge.projection_sequence = last_handled_sequence, projection_id = %self.projection_id, partition_id, database = "postgres");
                }
                (Some(_), _) => {}
            }
        }

        self.handler
            .flush(tx)
            .await
            .map_err(EventHandlerError::Handler)?;

        self.transaction
            .take()
            .unwrap()
            .commit()
            .await
            .map_err(|err| EventHandlerError::Processor(err.into()))?;

        self.handler
            .after_commit()
            .await
            .map_err(EventHandlerError::Handler)?;

        self.last_flushed_sequences = self.last_handled_sequences.clone();
        self.events_since_flush = 0;
        self.last_flushed = Instant::now();

        Ok(())
    }

    fn replay_progress_percent(&self) -> f64 {
        let mut total_events = 0u64;
        let mut processed_events = 0u64;

        for (partition_id, latest_sequence) in &self.partition_latest_sequences {
            // Latest sequence is 0-indexed, so +1 for total count
            if let Some(latest) = latest_sequence {
                total_events += latest + 1;

                // Get how many we've processed in this partition
                if let Some(last_handled) = self.last_handled_sequences.get(partition_id) {
                    processed_events += last_handled + 1;
                }
                // If not in last_handled yet, we've processed 0 events for this partition
            }
        }

        if total_events == 0 {
            return 100.0; // No events to process
        }

        (processed_events as f64 / total_events as f64) * 100.0
    }
}

async fn handle_event<'a, E, H>(
    (pool, transaction, handler, event): (
        &'a PgPool,
        &'a mut Option<sqlx::Transaction<'static, Postgres>>,
        &'a mut H,
        &'a Event,
    ),
) -> (
    (
        &'a PgPool,
        &'a mut Option<sqlx::Transaction<'static, Postgres>>,
        &'a mut H,
        &'a Event,
    ),
    Result<
        (),
        EventHandlerError<
            PostgresEventProcessorError,
            <H as EventHandler<sqlx::Transaction<'static, Postgres>>>::Error,
        >,
    >,
)
where
    E: 'static,
    H: EventHandler<sqlx::Transaction<'static, Postgres>>
        + CompositeEventHandler<E, sqlx::Transaction<'static, Postgres>, PostgresEventProcessorError>
        + Send
        + 'static,
{
    let mut tx = match transaction.take() {
        Some(tx) => tx,
        None => {
            let tx_res = pool.begin().await;
            match tx_res {
                Ok(tx) => tx,
                Err(err) => return ((pool, transaction, handler, event), Err(err.into())),
            }
        }
    };

    // Issue #37 review: isolate each event in a nested SAVEPOINT so a failing
    // event never discards the effects of earlier successful events that are
    // still unflushed in this batch transaction. Without the savepoint the
    // rollback below would lose those effects while the dead-letter path
    // advances the checkpoint past them — silent data loss on replay.
    //
    // Raw `SAVEPOINT`/`ROLLBACK TO`/`RELEASE` statements are used instead of
    // sqlx's nested-transaction API because the handler context type is
    // `Transaction<'static, Postgres>` (a savepoint `Transaction` borrowing
    // `tx` is not `'static`). The name embeds only numeric coordinates, so
    // identifier injection is impossible; retries reuse the same name safely
    // because the previous attempt's savepoint was released or rolled back.
    let savepoint = format!(
        "kameo_es_sp_{}_{}",
        event.partition_id, event.partition_sequence
    );

    let begin_sp = sqlx::query(AssertSqlSafe(format!("SAVEPOINT {savepoint}")))
        .execute(&mut *tx)
        .await;
    if let Err(err) = begin_sp {
        error!("failed to start event savepoint: {err:?}");
        // Likely a broken connection — drop the batch (replay-safe: the
        // checkpoint never advanced past the earlier events).
        *transaction = None;
        return (
            (pool, transaction, handler, event),
            Err(EventHandlerError::Processor(err.into())),
        );
    }

    let res = handler.composite_handle(&mut tx, event.clone()).await;
    if res.is_err() {
        match sqlx::query(AssertSqlSafe(format!("ROLLBACK TO SAVEPOINT {savepoint}")))
            .execute(&mut *tx)
            .await
        {
            Ok(_) => {
                // Retain the transaction: it still holds the earlier
                // successful events' effects. The poison path commits them
                // atomically with the dead-letter row and the checkpoint
                // advance; a transient error propagates and the epoch
                // restart re-processes from the checkpoint.
                *transaction = Some(tx);
            }
            Err(err) => {
                error!("failed to roll back event savepoint: {err:?}");
                // The batch transaction is in an unknown state — drop it;
                // replay from the checkpoint covers the earlier events.
                *transaction = None;
            }
        }
        return ((pool, transaction, handler, event), res);
    }

    if let Err(err) = sqlx::query(AssertSqlSafe(format!("RELEASE SAVEPOINT {savepoint}")))
        .execute(&mut *tx)
        .await
    {
        error!("failed to release event savepoint: {err:?}");
        // If the transaction is unusable the next flush fails and the epoch
        // restarts — replay-safe either way.
    }

    *transaction = Some(tx);
    ((pool, transaction, handler, event), Ok(()))
}

async fn flush_retry<'w, E, H>(
    (worker, reason): (&'w mut Worker<E, H>, FlushReason),
) -> (
    (&'w mut Worker<E, H>, FlushReason),
    Result<
        (),
        EventHandlerError<
            PostgresEventProcessorError,
            <H as EventHandler<sqlx::Transaction<'static, Postgres>>>::Error,
        >,
    >,
)
where
    E: 'static,
    H: EventHandler<sqlx::Transaction<'static, Postgres>>
        + CompositeEventHandler<E, sqlx::Transaction<'static, Postgres>, PostgresEventProcessorError>
        + Send
        + 'static,
    <H as EventHandler<sqlx::Transaction<'static, Postgres>>>::Error:
        fmt::Debug + Sync + crate::event_handler::EventErrorClassify,
{
    let res = worker.flush_checkpoint(reason).await;
    ((worker, reason), res)
}

impl<E, H> Actor for Worker<E, H>
where
    E: 'static,
    H: EventHandler<sqlx::Transaction<'static, Postgres>>
        + CompositeEventHandler<E, sqlx::Transaction<'static, Postgres>, PostgresEventProcessorError>
        + Send
        + 'static,
    <H as EventHandler<sqlx::Transaction<'static, Postgres>>>::Error:
        fmt::Debug + Sync + crate::event_handler::EventErrorClassify,
{
    type Args = Self;
    type Error = anyhow::Error;

    async fn on_start(state: Self::Args, _actor_ref: ActorRef<Self>) -> Result<Self, Self::Error> {
        Ok(state)
    }

    async fn on_panic(
        &mut self,
        _actor_ref: WeakActorRef<Self>,
        err: PanicError,
    ) -> Result<ControlFlow<ActorStopReason>, Self::Error> {
        error!("PartitionWorker panicked: {err:?}");
        Ok(ControlFlow::Break(ActorStopReason::Panicked(err)))
    }

    async fn next(
        &mut self,
        _actor_ref: WeakActorRef<Self>,
        mailbox_rx: &mut MailboxReceiver<Self>,
    ) -> Result<Option<Signal<Self>>, Self::Error> {
        let last_flush_duration = self.last_flushed.elapsed();
        let flush_sleep_duration = if self.is_live {
            self.flush_live_interval_time
                .checked_sub(last_flush_duration)
        } else {
            self.flush_replay_interval_time
                .checked_sub(last_flush_duration)
        };
        let flush_sleep = OptionFuture::from(flush_sleep_duration.map(tokio::time::sleep));

        tokio::select! {
            msg = mailbox_rx.recv() => return Ok(msg),
            _ = flush_sleep => {
                flush_retry
                    .retry(ExponentialBuilder::new())
                    .context((self, FlushReason::TimeInterval))
                    .notify(|err, _dur| {
                        error!("failed to flush events: {err:?}");
                    })
                    .await
                    .1.unwrap();
            }
        }

        Ok(mailbox_rx.recv().await)
    }
}

impl<E, H> Message<HandleEvent> for Worker<E, H>
where
    E: 'static,
    H: EventHandler<sqlx::Transaction<'static, Postgres>>
        + CompositeEventHandler<E, sqlx::Transaction<'static, Postgres>, PostgresEventProcessorError>
        + Send
        + 'static,
    <H as EventHandler<sqlx::Transaction<'static, Postgres>>>::Error:
        fmt::Debug + Sync + crate::event_handler::EventErrorClassify,
{
    type Reply = Result<
        (),
        EventHandlerError<
            PostgresEventProcessorError,
            <H as EventHandler<sqlx::Transaction<'static, Postgres>>>::Error,
        >,
    >;

    async fn handle(
        &mut self,
        HandleEvent(event): HandleEvent,
        _ctx: &mut Context<Self, Self::Reply>,
    ) -> Self::Reply {
        self.handle_event(event).await
    }
}

#[derive(Debug, Error)]
pub enum PostgresEventProcessorError {
    #[error(transparent)]
    GetStartFrom(#[from] SendError<(), sqlx::Error>),
    #[error(transparent)]
    UndecodableSierraMessage(#[from] crate::TryFromSierraEventError),
    #[error(transparent)]
    Postgres(#[from] sqlx::Error),
    #[error("unexpected last event id, expected {expected:?}")]
    UnexpectedLastEventId { expected: Option<u64> },
    #[error("partition id {0} does not fit the SMALLINT checkpoint column")]
    InvalidPartitionId(u16),
}

/// Converts a domain partition id (`u16`) into the `SMALLINT` (`i16`) storage
/// representation of the checkpoints table. Partition ids are far below
/// `i16::MAX` in practice; out-of-range values become an explicit error
/// instead of a wrapping `as i16` cast or a panic (issue #392).
fn partition_id_to_smallint(partition_id: u16) -> Result<i16, PostgresEventProcessorError> {
    i16::try_from(partition_id)
        .map_err(|_| PostgresEventProcessorError::InvalidPartitionId(partition_id))
}

impl<H> From<sqlx::Error> for EventHandlerError<PostgresEventProcessorError, H> {
    fn from(err: sqlx::Error) -> Self {
        EventHandlerError::Processor(PostgresEventProcessorError::Postgres(err))
    }
}

#[derive(Clone, Copy, Debug)]
pub enum FlushReason {
    TimeInterval,
    LiveEventsInterval,
    ReplayEventsInterval,
}
