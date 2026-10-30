// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3 (neuralwatt)

//! Keep-list export and verbatim replay (issue #770, level `business`).
//!
//! SierraDB 0.3.1 offers no selective deletion and no enumeration (`KEYS`,
//! `SCAN` and `EDELETE` all answer `-INVALIDARG unknown command`), so
//! "delete the business streams, keep the configuration" is impossible at the
//! store level. The only way to keep the configuration across a store wipe is
//! therefore **export → wipe → replay**:
//!
//! * the stream ids of the keep categories come from their projections (the
//!   only enumeration the stack offers),
//! * each stream is read back with `ESCAN` and captured **verbatim** (payload
//!   and metadata bytes, event name, event id, timestamp),
//! * after the wipe the events are appended again with `EMAPPEND`, in order,
//!   on the same stream id — the store assigns the same stream versions, so the
//!   replayed history is byte-identical from the projectors' point of view.

use std::time::{Duration, SystemTime, UNIX_EPOCH};

use chrono::{DateTime, Utc};
use redis::aio::MultiplexedConnection;
use serde::{Deserialize, Serialize};
use sierradb_client::{
    AsyncTypedCommands, EMAppendEvent, ExpectedVersion, SierraError, stream_partition_key,
};
use sqlx::PgPool;
use uuid::Uuid;

use super::classification::{AggregateCategory, AggregateClass};

/// Format version of the export document — bump when the shape changes.
pub const EXPORT_FORMAT_VERSION: u32 = 1;

/// One event, captured verbatim.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ExportedEvent {
    /// The event-store stream (`<category>-<uuid>`).
    pub stream_id: String,
    /// The store's event name (`SceneCreated`, `ReservationReserved`, …).
    pub event_name: String,
    pub event_id: Uuid,
    pub stream_version: u64,
    /// Unix milliseconds, as SierraDB stores it.
    pub timestamp_millis: u64,
    /// CBOR payload bytes, hex-encoded so the document stays plain JSON.
    pub payload_hex: String,
    /// CBOR metadata bytes, hex-encoded.
    pub metadata_hex: String,
}

/// All events of one keep-list stream, in stream order.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ExportedStream {
    pub stream_id: String,
    pub category: String,
    pub events: Vec<ExportedEvent>,
}

/// The keep-list export written to `<backup>/keep-list.json`.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct KeepListExport {
    pub format_version: u32,
    pub created_at: DateTime<Utc>,
    pub database_target: String,
    pub streams: Vec<ExportedStream>,
}

impl KeepListExport {
    pub fn event_count(&self) -> usize {
        self.streams.iter().map(|stream| stream.events.len()).sum()
    }
}

/// Keep categories, in registry order.
pub fn keep_categories() -> impl Iterator<Item = AggregateCategory> {
    AggregateCategory::ALL
        .into_iter()
        .filter(|category| category.class() == AggregateClass::Keep)
}

/// Static `SELECT id` statement for a keep category's projection table.
///
/// `None` for reset categories: only the keep list is exported.
pub const fn keep_id_sql(category: AggregateCategory) -> Option<&'static str> {
    match category {
        AggregateCategory::AiConfig => Some("SELECT id FROM ai_import.projection_ai_config"),
        AggregateCategory::Settings => Some("SELECT id FROM projection_settings"),
        AggregateCategory::Membership => Some("SELECT id FROM projection_membership"),
        _ => None,
    }
}

/// Builds the stream id the `kameo_es` entity convention uses.
pub fn stream_id(category: AggregateCategory, id: Uuid) -> String {
    format!("{}-{}", category.as_str(), id)
}

/// Reads every keep-list stream into an export document.
pub async fn export_keep_list(
    pool: &PgPool,
    connection: &mut MultiplexedConnection,
    database_target: &str,
) -> Result<KeepListExport, anyhow::Error> {
    let mut streams = Vec::new();
    for category in keep_categories() {
        let sql = keep_id_sql(category).ok_or_else(|| {
            anyhow::anyhow!("keep category {} has no id query", category.as_str())
        })?;
        let ids: Vec<Uuid> = sqlx::query_scalar(sql).fetch_all(pool).await?;
        for id in ids {
            let stream = stream_id(category, id);
            let events = read_stream(connection, &stream).await?;
            tracing::info!(
                category = category.as_str(),
                stream = %stream,
                events = events.len(),
                "exported keep-list stream"
            );
            streams.push(ExportedStream {
                stream_id: stream,
                category: category.as_str().to_string(),
                events,
            });
        }
    }
    Ok(KeepListExport {
        format_version: EXPORT_FORMAT_VERSION,
        created_at: Utc::now(),
        database_target: database_target.to_string(),
        streams,
    })
}

/// Reads one stream verbatim (`ESCAN` in pages, in stream order).
pub async fn read_stream(
    connection: &mut MultiplexedConnection,
    stream_id: &str,
) -> Result<Vec<ExportedEvent>, anyhow::Error> {
    let mut events = Vec::new();
    let mut from_version = 0u64;
    loop {
        let batch = connection
            .escan(stream_id, from_version, None, Some(500))
            .await
            .map_err(SierraError::from)
            .map_err(|error| anyhow::anyhow!("ESCAN {stream_id}: {error}"))?;
        let last = batch.events.last().map(|event| event.stream_version);
        for event in batch.events {
            events.push(ExportedEvent {
                stream_id: event.stream_id,
                event_name: event.event_name,
                event_id: event.event_id,
                stream_version: event.stream_version,
                timestamp_millis: event
                    .timestamp
                    .duration_since(UNIX_EPOCH)
                    .unwrap_or_default()
                    .as_millis() as u64,
                payload_hex: to_hex(&event.payload),
                metadata_hex: to_hex(&event.metadata),
            });
        }
        if !batch.has_more {
            return Ok(events);
        }
        match last {
            Some(version) => from_version = version + 1,
            None => return Ok(events),
        }
    }
}

/// Replays an export into the (empty) event store, one stream at a time.
///
/// Returns the number of appended events. A stream is appended in a single
/// `EMAPPEND` call so its events keep their relative order and land on the same
/// partition key as before the wipe.
pub async fn replay_keep_list(
    connection: &mut MultiplexedConnection,
    export: &KeepListExport,
) -> Result<usize, anyhow::Error> {
    if export.format_version != EXPORT_FORMAT_VERSION {
        return Err(anyhow::anyhow!(
            "keep-list export has format version {} but this binary replays version {}",
            export.format_version,
            EXPORT_FORMAT_VERSION
        ));
    }
    let mut appended = 0usize;
    for stream in &export.streams {
        if stream.events.is_empty() {
            continue;
        }
        let partition_key = stream_partition_key(&stream.stream_id);
        let mut events = Vec::with_capacity(stream.events.len());
        for event in &stream.events {
            let payload = from_hex(&event.payload_hex)?;
            let metadata = from_hex(&event.metadata_hex)?;
            events.push(
                EMAppendEvent::new(stream.stream_id.clone(), event.event_name.clone())
                    .event_id(event.event_id)
                    .expected_version(ExpectedVersion::Any)
                    .timestamp(UNIX_EPOCH + Duration::from_millis(event.timestamp_millis))
                    .payload(payload)
                    .metadata(metadata),
            );
        }
        let count = events.len();
        connection
            .emappend(partition_key, &events)
            .await
            .map_err(|error| {
                anyhow::anyhow!("EMAPPEND {} ({} events): {error}", stream.stream_id, count)
            })?;
        appended += count;
        tracing::info!(
            stream = %stream.stream_id,
            events = count,
            "replayed keep-list stream"
        );
    }
    Ok(appended)
}

/// `ai_model_pricing` rows as JSON — exported for the backup, deliberately not
/// deleted (the cost snapshot depends on them).
pub async fn export_pricing(pool: &PgPool) -> Result<Vec<serde_json::Value>, anyhow::Error> {
    let rows: Vec<serde_json::Value> =
        sqlx::query_scalar("SELECT to_jsonb(t) FROM ai_import.ai_model_pricing t")
            .fetch_all(pool)
            .await?;
    Ok(rows)
}

/// Restores pricing rows from a backup (only used when the table came up empty).
pub async fn restore_pricing(
    pool: &PgPool,
    rows: &[serde_json::Value],
) -> Result<u64, anyhow::Error> {
    if rows.is_empty() {
        return Ok(0);
    }
    let document = serde_json::Value::Array(rows.to_vec());
    let restored = sqlx::query(
        r#"
        INSERT INTO ai_import.ai_model_pricing
        SELECT * FROM jsonb_populate_recordset(NULL::ai_import.ai_model_pricing, $1::jsonb)
        ON CONFLICT DO NOTHING
        "#,
    )
    .bind(document)
    .execute(pool)
    .await?
    .rows_affected();
    Ok(restored)
}

fn to_hex(bytes: &[u8]) -> String {
    let mut out = String::with_capacity(bytes.len() * 2);
    for byte in bytes {
        out.push_str(&format!("{byte:02x}"));
    }
    out
}

fn from_hex(text: &str) -> Result<Vec<u8>, anyhow::Error> {
    if !text.len().is_multiple_of(2) {
        return Err(anyhow::anyhow!("hex payload has an odd length"));
    }
    let mut bytes = Vec::with_capacity(text.len() / 2);
    let raw = text.as_bytes();
    let mut index = 0;
    while index < raw.len() {
        let high = hex_digit(raw[index])?;
        let low = hex_digit(raw[index + 1])?;
        bytes.push(high * 16 + low);
        index += 2;
    }
    Ok(bytes)
}

fn hex_digit(byte: u8) -> Result<u8, anyhow::Error> {
    match byte {
        b'0'..=b'9' => Ok(byte - b'0'),
        b'a'..=b'f' => Ok(byte - b'a' + 10),
        b'A'..=b'F' => Ok(byte - b'A' + 10),
        other => Err(anyhow::anyhow!(
            "invalid hex digit {:?} in payload",
            other as char
        )),
    }
}

/// Wall-clock helper shared with the backup manifest.
pub fn unix_millis(instant: SystemTime) -> u64 {
    instant
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis() as u64
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn hex_round_trips_payloads() {
        for bytes in [
            Vec::new(),
            vec![0u8],
            vec![0, 255, 16, 127],
            (0u8..=255).collect::<Vec<_>>(),
        ] {
            let encoded = to_hex(&bytes);
            assert_eq!(from_hex(&encoded).unwrap(), bytes);
        }
    }

    #[test]
    fn hex_rejects_malformed_input() {
        assert!(from_hex("abc").is_err());
        assert!(from_hex("zz").is_err());
    }

    #[test]
    fn keep_categories_are_the_configuration_triple() {
        let categories: Vec<&str> = keep_categories().map(|c| c.as_str()).collect();
        assert_eq!(categories, vec!["ai_config", "settings", "membership"]);
    }

    #[test]
    fn only_keep_categories_have_id_queries() {
        for category in AggregateCategory::ALL {
            match category.class() {
                AggregateClass::Keep => {
                    assert!(
                        keep_id_sql(category).is_some(),
                        "{} must expose its stream ids",
                        category.as_str()
                    );
                }
                AggregateClass::Reset => {
                    assert!(
                        keep_id_sql(category).is_none(),
                        "{} is business data and must not be exported",
                        category.as_str()
                    );
                }
            }
        }
    }

    #[test]
    fn stream_id_follows_the_entity_convention() {
        let id = Uuid::now_v7();
        assert_eq!(
            stream_id(AggregateCategory::AiConfig, id),
            format!("ai_config-{id}")
        );
        assert_eq!(
            stream_id(AggregateCategory::Membership, id),
            format!("membership-{id}")
        );
    }

    #[test]
    fn export_document_round_trips_through_json() {
        let export = KeepListExport {
            format_version: EXPORT_FORMAT_VERSION,
            created_at: Utc::now(),
            database_target: "localhost/breakdown".to_string(),
            streams: vec![ExportedStream {
                stream_id: "ai_config-0199a0c0-0000-7000-8000-000000000000".to_string(),
                category: "ai_config".to_string(),
                events: vec![ExportedEvent {
                    stream_id: "ai_config-0199a0c0-0000-7000-8000-000000000000".to_string(),
                    event_name: "AiConfigCreated".to_string(),
                    event_id: Uuid::now_v7(),
                    stream_version: 0,
                    timestamp_millis: 1_700_000_000_000,
                    payload_hex: "deadbeef".to_string(),
                    metadata_hex: String::new(),
                }],
            }],
        };
        let json = serde_json::to_string(&export).unwrap();
        let parsed: KeepListExport = serde_json::from_str(&json).unwrap();
        assert_eq!(parsed, export);
        assert_eq!(parsed.event_count(), 1);
    }
}
