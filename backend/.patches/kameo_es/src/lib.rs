// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors

pub mod command_service;
pub mod connection_pool;
pub mod entity_actor;
pub mod error;
pub mod event_handler;
pub mod transaction;
// Append counters for the caller's own attribution (issue #900, M2).
pub mod write_metrics;

pub use connection_pool::ConnectionPool;
pub use write_metrics::{append_metrics, AppendMetrics};

use std::{convert::Infallible, io, time::SystemTime};

use jiff::Timestamp;

use kameo::error::SendError;
use sierradb_client::SierraError;
use thiserror::Error;

pub use kameo_es_core::*;

#[derive(Debug, Error)]
pub enum Error<M = (), E = Infallible> {
    #[error(transparent)]
    Database(#[from] SierraError),
    #[error(transparent)]
    SendError(#[from] SendError<M, E>),
}

/// Bridge between the domain instant (`jiff::Timestamp`) and the `SystemTime`
/// the SierraDB wire protocol carries (ADR-040, issue #929).
///
/// `chrono` implemented both directions as `From`, which is why the append and
/// replay paths converted with a bare `.into()`. jiff's conversions are
/// `TryFrom`: `Timestamp` spans ±9_999 years while `SystemTime`'s range is
/// platform-defined (Windows starts at 1601). Neither direction may be
/// silently clamped — an append timestamp that got folded to the epoch would
/// corrupt the stream's ordering — so both stay fallible and the callers map
/// the failure onto their existing `InvalidTimestamp` variant.
pub(crate) fn to_system_time(ts: Timestamp) -> Result<SystemTime, jiff::Error> {
    SystemTime::try_from(ts)
}

/// Inverse of [`to_system_time`]; a store-supplied instant outside
/// `Timestamp`'s range is a corrupt-event error, not a replay abort.
pub(crate) fn from_system_time(time: SystemTime) -> Result<Timestamp, jiff::Error> {
    Timestamp::try_from(time)
}

/// A failure to convert a raw Sierra message into a typed [`Event`]
/// (issue #411): the raw message is preserved so the stream layer can
/// dead-letter it durably (DLQ row + checkpoint advance) instead of
/// restart-looping the projector on the same malformed message.
#[derive(Debug, Error)]
pub enum TryFromSierraEventError {
    // The raw message is boxed to keep the `Err` size within clippy's
    // `result_large_err` budget ( EventHandlerError embeds this type).
    #[error("failed to deserialize event data: {err}")]
    DeserializeEventData {
        event: Box<sierradb_client::Event>,
        err: ciborium::de::Error<io::Error>,
    },
    #[error("failed to deserialize event metadata: {err}")]
    DeserializeEventMetadata {
        event: Box<sierradb_client::Event>,
        err: ciborium::de::Error<io::Error>,
    },
    /// The stored event carries an instant `jiff::Timestamp` cannot represent
    /// (ADR-040). Permanent by construction: the same message replays the same
    /// way, so the stream layer dead-letters it instead of restart-looping.
    #[error("event timestamp out of range: {err}")]
    TimestampOutOfRange {
        event: Box<sierradb_client::Event>,
        err: jiff::Error,
    },
}

fn event_from_sierra(ev: sierradb_client::Event) -> Result<Event, TryFromSierraEventError> {
    // Converted before the struct is consumed field by field: a store instant
    // outside `Timestamp`'s range must surface as a typed error, not as a
    // partially moved value.
    let timestamp = from_system_time(ev.timestamp).map_err(|err| {
        TryFromSierraEventError::TimestampOutOfRange {
            event: Box::new(ev.clone()),
            err,
        }
    })?;
    let data = if !ev.payload.is_empty() {
        ciborium::from_reader(ev.payload.as_slice()).map_err(|err| {
            TryFromSierraEventError::DeserializeEventData {
                event: Box::new(ev.clone()),
                err,
            }
        })?
    } else {
        GenericValue(ciborium::Value::Null)
    };
    let metadata = if !ev.metadata.is_empty() {
        ciborium::from_reader(ev.metadata.as_slice()).map_err(|err| {
            TryFromSierraEventError::DeserializeEventMetadata {
                event: Box::new(ev.clone()),
                err,
            }
        })?
    } else {
        Metadata::default()
    };

    Ok(Event {
        id: ev.event_id,
        partition_key: ev.partition_key,
        partition_id: ev.partition_id,
        transaction_id: ev.transaction_id,
        partition_sequence: ev.partition_sequence,
        stream_version: ev.stream_version,
        stream_id: StreamId::new(ev.stream_id),
        name: ev.event_name,
        data,
        metadata,
        timestamp,
    })
}

/// Matches on an event for multiple branches, with each branch being an entity type.
///
/// The passed in event will be converted to Event<E> where E is the Entity for the given branch.
///
/// # Example
///
/// ```ignore
/// // Example usage of the match_event! macro.
/// // BankAccount needs to implement the Entity trait.
/// kameo_es::match_event! {
///     event,
///     BankAccount => {
///         let id: <BankAccount as kameo_es::Entity>::ID = event.entity_id()?;
///         let data: <BankAccount as kameo_es::Entity>::Event = event.data;
///         // ...
///     }
///     else => println!("unknown entity"),
/// }
/// ```
#[macro_export]
macro_rules! match_event {
    // All input is normalized, now transform.
    (@ {
        event=$event:ident;

        $( $ent:ident => $handle:expr, )+

        // Fallback expression used when all select branches have been disabled.
        ; $else:expr

    }) => {{
        let category = $event.stream_id.category();
        $(
            if category == <$ent as $crate::Entity>::category() {
                let $event = $event.as_entity::<$ent>();
                {
                    $handle
                }
            } else
        )*
        if true {
            $else
        } else {
            unreachable!()
        }
    }};

    // ==== Normalize =====

    // These rules match a single `select!` branch and normalize it for
    // processing by the first rule.

    (@ { event=$event:ident; $($t:tt)* } ) => {
        // No `else` branch
        $crate::match_event!(@{ event=$event; $($t)*; {} })
    };
    (@ { event=$event:ident; $($t:tt)* } else => $else:expr $(,)?) => {
        $crate::match_event!(@{ event=$event; $($t)*; $else })
    };
    (@ { event=$event:ident; $($t:tt)* } $ent:ident => $h:block, $($r:tt)* ) => {
        $crate::match_event!(@{ event=$event; $($t)* $ent => $h, } $($r)*)
    };
    (@ { event=$event:ident; $($t:tt)* } $ent:ident => $h:block $($r:tt)* ) => {
        $crate::match_event!(@{ event=$event; $($t)* $ent => $h, } $($r)*)
    };
    (@ { event=$event:ident; $($t:tt)* } $ent:ident => $h:expr ) => {
        $crate::match_event!(@{ event=$event; $($t)* $ent => $h, })
    };
    (@ { event=$event:ident; $($t:tt)* } $ent:ident => $h:expr, $($r:tt)* ) => {
        $crate::match_event!(@{ event=$event; $($t)* $ent => $h, } $($r)*)
    };

    // ===== Entry point =====

    ( $event:ident, else => $else:expr $(,)? ) => {{
        $else
    }};

    ( $event:ident, $ent:ident => $($t:tt)* ) => {
        // Randomly generate a starting point. This makes `select!` a bit more
        // fair and avoids always polling the first future.
        $crate::match_event!(@{ event=$event; } $ent => $($t)*)
    };

    () => {
        compile_error!("select! requires at least one branch.")
    };
}
