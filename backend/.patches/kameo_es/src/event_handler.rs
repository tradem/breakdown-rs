// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4-flash (opencode-go)

#[cfg(feature = "postgres")]
pub mod postgres;

use std::{collections::HashMap, marker::PhantomData};

use futures::Future;
use redis::RedisError;
use sierradb_client::{EventSubscription, SierraError, SierraMessage, SubscriptionManager};
use thiserror::Error;
use tracing::{debug, trace};

use crate::{event_from_sierra, Entity, Event, TryFromSierraEventError};

pub trait EventProcessor<E, H>
where
    Self: Send,
    H: EventHandler<Self::Context>,
{
    type Context: Send;
    type Error: Send;

    /// Which event to start streaming from.
    fn start_from(&self) -> impl Future<Output = Result<HashMap<u16, u64>, Self::Error>>;

    /// Processes an event, which should internally call the event handler.
    fn process_event(
        &mut self,
        event: Event,
    ) -> impl Future<Output = Result<(), EventHandlerError<Self::Error, H::Error>>> + Send;
}

/// An event handler.
pub trait EventHandler<C>: Send {
    type Error: Send;

    /// Handles an event, typically as a fallback when no entities were matched.
    fn handle(
        &mut self,
        _ctx: &mut C,
        _event: Event,
    ) -> impl Future<Output = Result<(), Self::Error>> + Send {
        async move { Ok(()) }
    }

    fn flush(&mut self, _ctx: &mut C) -> impl Future<Output = Result<(), Self::Error>> + Send {
        async move { Ok(()) }
    }

    fn after_commit(&mut self) -> impl Future<Output = Result<(), Self::Error>> + Send {
        async move { Ok(()) }
    }
}

/// An event handler for an entity.
pub trait EntityEventHandler<E, C>: EventHandler<C>
where
    E: Entity,
{
    /// Handles an event for an entity.
    fn handle(
        &mut self,
        ctx: &mut C,
        id: E::ID,
        event: Event<E::Event, E::Metadata>,
    ) -> impl Future<Output = Result<(), Self::Error>> + Send;
}

/// A trait for handling events based on a tuple of entities, where each entity is checked against the event category
/// in order until a match is found, which will then be handled using the `EntityEventHandler`.
pub trait CompositeEventHandler<E, C, PE>
where
    Self: EventHandler<C> + Sized,
{
    /// Handles an event, determining which entity it belongs to, falling back to the `EventHandler` implementation.
    fn composite_handle(
        &mut self,
        ctx: &mut C,
        event: Event,
    ) -> impl Future<Output = Result<(), EventHandlerError<PE, Self::Error>>> + Send;
}

/// A helper trait for creating an event handler stream.
pub trait EventHandlerStreamBuilder: Sized + 'static {
    fn event_handler_stream<P, H>(
        manager: &mut SubscriptionManager,
        processor: &mut P,
    ) -> impl Future<Output = Result<EventHandlerStream<Self>, EventHandlerError<P::Error, H::Error>>>
    where
        P: EventProcessor<Self, H>,
        H: EventHandler<P::Context>;
}

impl<E: 'static> EventHandlerStreamBuilder for E {
    async fn event_handler_stream<P, H>(
        manager: &mut SubscriptionManager,
        processor: &mut P,
    ) -> Result<EventHandlerStream<Self>, EventHandlerError<P::Error, H::Error>>
    where
        P: EventProcessor<Self, H>,
        H: EventHandler<P::Context>,
    {
        EventHandlerStream::new(manager, processor).await
    }
}

/// An error which occurs when handling an event.
#[derive(Debug, Error)]
pub enum EventHandlerError<P, H> {
    #[error("failed to deserialize event '{event}' for entity '{entity}': {err}")]
    DeserializeEvent {
        entity: &'static str,
        event: String,
        err: ciborium::value::Error,
    },
    #[error(transparent)]
    Sierra(#[from] SierraError),
    #[error("failed to parse entity id: {0}")]
    ParseID(String),
    #[error("{0}")]
    Processor(P),
    #[error("{0}")]
    Handler(H),
    #[error(transparent)]
    EventFromSierra(#[from] TryFromSierraEventError),
}

impl<P, H> From<RedisError> for EventHandlerError<P, H> {
    fn from(err: RedisError) -> Self {
        EventHandlerError::Sierra(err.into())
    }
}

/// A stream which processes events using an `EventProcessor`.
pub struct EventHandlerStream<E> {
    subscription: EventSubscription,
    /// Tracks the high-water cursor of *successfully processed* events and
    /// when a batch acknowledgement is due.
    ack: AckTracker,
    phantom: PhantomData<fn() -> E>,
}

impl<E> EventHandlerStream<E> {
    async fn new<P, H>(
        manager: &mut SubscriptionManager,
        processor: &mut P,
    ) -> Result<Self, EventHandlerError<P::Error, H::Error>>
    where
        E: 'static,
        P: EventProcessor<E, H>,
        H: EventHandler<P::Context>,
    {
        let start_from = processor
            .start_from()
            .await
            .map_err(EventHandlerError::Processor)?;
        let subscription = manager
            .subscribe_to_all_partitions_flexible(
                start_from,
                Some(0),
                Some(AckTracker::SUBSCRIPTION_WINDOW),
            )
            .await?;

        Ok(EventHandlerStream {
            subscription,
            ack: AckTracker::default(),
            phantom: PhantomData,
        })
    }

    pub async fn process_next<P, H>(
        &mut self,
        processor: &mut P,
    ) -> Option<Result<(), EventHandlerError<P::Error, H::Error>>>
    where
        E: 'static,
        P: EventProcessor<E, H>,
        H: EventHandler<P::Context>,
    {
        match self.next().await? {
            Ok(event) => Some(self.process_event_and_ack(processor, event).await),
            Err(err) => Some(Err(err.into())),
        }
    }

    pub async fn run<P, H>(
        &mut self,
        processor: &mut P,
    ) -> Result<(), EventHandlerError<P::Error, H::Error>>
    where
        E: 'static,
        P: EventProcessor<E, H>,
        H: EventHandler<P::Context>,
    {
        while let Some(unprocessed_event) = self.next().await.transpose()? {
            self.process_event_and_ack(processor, unprocessed_event)
                .await?;
        }
        // Flush the final partial acknowledgement batch before a clean exit
        // so already-processed events are not replayed after a restart.
        if let Some(ack_cursor) = self.ack.flush() {
            trace!("acknowledging up to cursor {ack_cursor} on clean exit");
            self.subscription
                .acknowledge_up_to_cursor(ack_cursor)
                .await
                .map_err(EventHandlerError::from)?;
        }
        Ok(())
    }

    pub async fn next(&mut self) -> Option<Result<UnprocessedEvent<E>, NextEventError>> {
        while let Some(event) = self.subscription.next_message().await {
            match event {
                SierraMessage::Event { event, cursor } => {
                    let event = match event_from_sierra(event) {
                        Ok(event) => event,
                        Err(err) => return Some(Err(err.into())),
                    };
                    return Some(Ok(UnprocessedEvent::new(event, cursor)));
                }
                SierraMessage::SubscriptionConfirmed { .. } => {}
            }
        }

        None
    }

    /// Process a single event and, on success, acknowledge its SierraDB
    /// cursor. The cursor is acknowledged **only after** the handler
    /// completed, so a failed event is never acknowledged and can be
    /// redelivered (projectors resume from their Postgres checkpoint) or
    /// retried (sagas retry transient failures in-loop).
    async fn process_event_and_ack<P, H>(
        &mut self,
        processor: &mut P,
        event: UnprocessedEvent<E>,
    ) -> Result<(), EventHandlerError<P::Error, H::Error>>
    where
        E: 'static,
        P: EventProcessor<E, H>,
        H: EventHandler<P::Context>,
    {
        let cursor = event.cursor;
        event.process(processor).await?;
        if let Some(ack_cursor) = self.ack.processed(cursor) {
            trace!("acknowledging up to cursor {ack_cursor}");
            self.subscription
                .acknowledge_up_to_cursor(ack_cursor)
                .await
                .map_err(EventHandlerError::from)?;
        }
        Ok(())
    }
}

#[derive(Debug, Error)]
pub enum NextEventError {
    #[error(transparent)]
    Sierra(#[from] SierraError),
    #[error(transparent)]
    DeserializeEvent(#[from] TryFromSierraEventError),
}

impl From<RedisError> for NextEventError {
    fn from(err: RedisError) -> Self {
        NextEventError::Sierra(err.into())
    }
}

impl<P, H> From<NextEventError> for EventHandlerError<P, H> {
    fn from(err: NextEventError) -> Self {
        match err {
            NextEventError::Sierra(err) => EventHandlerError::Sierra(err),
            NextEventError::DeserializeEvent(err) => EventHandlerError::EventFromSierra(err),
        }
    }
}

#[must_use = "the event has not been processed yet"]
pub struct UnprocessedEvent<E> {
    pub event: Event,
    /// SierraDB cursor for this event. Acknowledged only after the event was
    /// processed successfully.
    pub cursor: u64,
    phantom: PhantomData<fn() -> E>,
}

impl<E> UnprocessedEvent<E> {
    fn new(event: Event, cursor: u64) -> Self {
        UnprocessedEvent {
            event,
            cursor,
            phantom: PhantomData,
        }
    }

    pub async fn process<P, H>(
        self,
        processor: &mut P,
    ) -> Result<(), EventHandlerError<P::Error, H::Error>>
    where
        P: EventProcessor<E, H>,
        H: EventHandler<P::Context>,
    {
        debug!(
            "{:>2}:{:>6} {:<32} {:>6} > {}",
            self.event.partition_id,
            self.event.partition_sequence,
            self.event.stream_id,
            self.event.stream_version,
            self.event.name
        );
        processor.process_event(self.event).await
    }
}

/// Tracks the high-water cursor of *successfully processed* events and
/// decides when a batch acknowledgement is due.
///
/// Events are processed strictly sequentially and cursors are a monotonic
/// per-subscription sequence, so the cursor of the last processed event is
/// also the highest cursor that may be acknowledged.
///
/// `pub` so the deterministic tests in `tests/` can verify the
/// ack-after-processing contract without a live SierraDB subscription.
#[derive(Debug, Default, Clone, Copy)]
pub struct AckTracker {
    events_since_ack: u64,
    last_processed_cursor: Option<u64>,
}

impl AckTracker {
    /// SierraDB subscription delivery window; the ack batch size must stay
    /// below it so delivery never stalls behind the acknowledgement.
    pub const SUBSCRIPTION_WINDOW: u32 = 10_000;

    /// Batch size for flow-control acknowledgement. Kept below
    /// [`Self::SUBSCRIPTION_WINDOW`] so delivery never stalls behind the ack.
    pub const BATCH_SIZE: u64 = 8_000;

    /// Compile-time enforcement of the [`Self::BATCH_SIZE`] /
    /// [`Self::SUBSCRIPTION_WINDOW`] invariant.
    const _WINDOW_INVARIANT: () = assert!(Self::BATCH_SIZE < Self::SUBSCRIPTION_WINDOW as u64);

    /// Record a successfully processed event at `cursor`.
    ///
    /// Returns `Some(cursor)` when a batch acknowledgement should be sent —
    /// always the cursor of a *processed* event, never a
    /// received-but-unprocessed one.
    pub fn processed(&mut self, cursor: u64) -> Option<u64> {
        self.events_since_ack += 1;
        self.last_processed_cursor = Some(cursor);
        if self.events_since_ack >= Self::BATCH_SIZE {
            self.events_since_ack = 0;
            Some(cursor)
        } else {
            None
        }
    }

    /// Flush a pending partial batch, returning the highest successfully
    /// processed cursor that has not been acknowledged yet. Used at the end
    /// of a clean subscription run so a stream shorter than
    /// [`Self::BATCH_SIZE`] does not replay already-processed events on
    /// restart. Returns `None` when nothing is pending.
    pub fn flush(&mut self) -> Option<u64> {
        if self.events_since_ack > 0 {
            self.events_since_ack = 0;
            self.last_processed_cursor
        } else {
            None
        }
    }
}

macro_rules! impl_composite_event_handler {
    (
        $( ( $( $ent:ident ),* ), )+
    ) => {
        $(
            impl_composite_event_handler!( $( $ent ),* );
        )+
    };
    ( $( $( $ent:ident ),+ )? ) => {
        impl<H, C, PE $( , $( $ent ),+ )?> CompositeEventHandler<( $( $( $ent, )+ )? ), C, PE> for H
        where
            H: EventHandler<C> + Sized,
            C: Send,
            PE: Send,
            $( $(
                H: EntityEventHandler<$ent, C>,
                $ent: Entity,
            )+ )?
        {
            async fn composite_handle(
                &mut self,
                ctx: &mut C,
                event: Event,
            ) -> Result<(), EventHandlerError<PE, Self::Error>> {
                $(
                    let category = event.stream_id.category();
                    $(
                        if category == $ent::category() {
                            EntityEventHandler::<$ent, C>::handle(
                                self,
                                ctx,
                                event.entity_id::<$ent>().map_err(|_| {
                                    EventHandlerError::ParseID(event.stream_id.cardinal_id().to_string())
                                })?,
                                event.as_entity::<$ent>().map_err(|(event, err)| {
                                    EventHandlerError::DeserializeEvent {
                                        entity: $ent::category(),
                                        event: event.name,
                                        err,
                                    }
                                })?,
                            )
                            .await
                            .map_err(EventHandlerError::Handler)
                        } else
                    )+
                )?

                {
                    EventHandler::handle(self, ctx, event)
                        .await
                        .map_err(EventHandlerError::Handler)
                }
            }
        }
    };
}

impl_composite_event_handler![
    (),
    (E1),
    (E1, E2),
    (E1, E2, E3),
    (E1, E2, E3, E4),
    (E1, E2, E3, E4, E5),
    (E1, E2, E3, E4, E5, E6),
    (E1, E2, E3, E4, E5, E6, E7),
    (E1, E2, E3, E4, E5, E6, E7, E8),
    (E1, E2, E3, E4, E5, E6, E7, E8, E9),
    (E1, E2, E3, E4, E5, E6, E7, E8, E9, E10),
    (E1, E2, E3, E4, E5, E6, E7, E8, E9, E10, E11),
    (E1, E2, E3, E4, E5, E6, E7, E8, E9, E10, E11, E12),
    (E1, E2, E3, E4, E5, E6, E7, E8, E9, E10, E11, E12, E13),
    (E1, E2, E3, E4, E5, E6, E7, E8, E9, E10, E11, E12, E13, E14),
    (E1, E2, E3, E4, E5, E6, E7, E8, E9, E10, E11, E12, E13, E14, E15),
    (E1, E2, E3, E4, E5, E6, E7, E8, E9, E10, E11, E12, E13, E14, E15, E16),
];
