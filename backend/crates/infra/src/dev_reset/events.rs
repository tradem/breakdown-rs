// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3 (neuralwatt)
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

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

    /// Per-category stream/event counts, in registry order (issue #810).
    ///
    /// The plan can only count **rows** (it is PostgreSQL-only by design); this
    /// is the event-side view an operator needs to see `ai_config: 0 events`
    /// *before* the volume goes.
    pub fn category_counts(&self) -> Vec<CategoryEventCount> {
        let mut counts = Vec::new();
        for category in keep_categories() {
            let streams: Vec<&ExportedStream> = self
                .streams
                .iter()
                .filter(|stream| stream.category == category.as_str())
                .collect();
            if streams.is_empty() {
                continue;
            }
            counts.push(CategoryEventCount {
                category,
                streams: streams.len(),
                events: streams.iter().map(|stream| stream.events.len()).sum(),
            });
        }
        counts
    }
}

/// One keep category's share of an export (issue #810).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct CategoryEventCount {
    pub category: AggregateCategory,
    pub streams: usize,
    pub events: usize,
}

/// Keep categories, in registry order.
pub fn keep_categories() -> impl Iterator<Item = AggregateCategory> {
    AggregateCategory::ALL
        .into_iter()
        .filter(|category| category.class() == AggregateClass::Keep)
}

/// Static `SELECT <entity id>` statement for a keep category's projection
/// table.
///
/// The selected column must be the aggregate's **`Entity::ID`**, because the
/// stream id is `<category>-<entity id>` — not necessarily a column called `id`:
/// the `membership` aggregate is keyed by its **block id**
/// (`projection_membership` has the composite PK `(block_id, user_id)` and no
/// `id` column at all), so it selects the distinct block ids.
///
/// `None` for reset categories: only the keep list is exported.
pub const fn keep_id_sql(category: AggregateCategory) -> Option<&'static str> {
    match category {
        AggregateCategory::AiConfig => Some("SELECT id FROM ai_import.projection_ai_config"),
        AggregateCategory::Settings => Some("SELECT id FROM projection_settings"),
        AggregateCategory::Membership => {
            Some("SELECT DISTINCT block_id FROM projection_membership")
        }
        // One stream per PROJECT (openspec change `project-scoped-membership`):
        // the project-membership aggregate is keyed by its project id, so the
        // distinct ids of the projection's `project_id` column are the streams.
        AggregateCategory::ProjectMembership => {
            Some("SELECT DISTINCT project_id FROM projection_project_membership")
        }
        _ => None,
    }
}

/// Builds the stream id the `kameo_es` entity convention uses.
pub fn stream_id(category: AggregateCategory, id: Uuid) -> String {
    format!("{}-{}", category.as_str(), id)
}

/// Refuses an export that would silently drop a non-empty keep category.
///
/// Returns an error when a keep projection holds rows but its stream ids could
/// not be resolved (a wrong id column, an empty id list) — exporting nothing and
/// then wiping would lose the configuration this level exists to preserve.
pub fn ensure_streams_resolved(
    category: AggregateCategory,
    projection_rows: i64,
    resolved_streams: usize,
) -> Result<(), anyhow::Error> {
    if projection_rows > 0 && resolved_streams == 0 {
        return Err(anyhow::anyhow!(
            "refusing to export the keep list: {} holds {} row(s) but no event stream could be \
             resolved from {} — fix `keep_id_sql` before wiping",
            category.projection_table(),
            projection_rows,
            category.as_str()
        ));
    }
    Ok(())
}

/// Refuses an export in which a keep **category** holds projection rows but its
/// streams carry **no events** (issue #810).
///
/// That combination has exactly one explanation: the keep projections survived
/// while the event store was already emptied (a previous run failed after the
/// volume drop). Exporting it and replaying it appends nothing, which turns a
/// recoverable incident into a permanent loss of the configuration — so the
/// export fails instead. `--allow-empty-keep-list` is the explicit override for
/// an operator who really means to start without a configuration.
///
/// The check is **per category**, not on the total: on 2026-11-03 `ai_config`
/// and `settings` rows were both present while their streams were gone, and an
/// eventless `ai_config` next to a non-empty `settings` would slip through a
/// total-only check — the wipe deletes its projection, the replay skips its
/// empty stream, and verification accepts the result.
pub fn ensure_events_exported(
    export: &KeepListExport,
    keep_rows: &[(AggregateCategory, i64)],
    allow_empty_keep_list: bool,
) -> Result<(), anyhow::Error> {
    if allow_empty_keep_list {
        return Ok(());
    }
    let mut eventless = Vec::new();
    for (category, rows) in keep_rows {
        if *rows <= 0 {
            continue;
        }
        let events: usize = export
            .streams
            .iter()
            .filter(|stream| stream.category == category.as_str())
            .map(|stream| stream.events.len())
            .sum();
        if events == 0 {
            eventless.push(format!("{}: {rows} row(s) / 0 events", category.as_str()));
        }
    }
    if eventless.is_empty() {
        return Ok(());
    }
    Err(anyhow::anyhow!(
        "refusing to export the keep list: the event store returned no events for keep \
         categor(y/ies) that still hold projection rows ({}). The event store is already empty \
         and the configuration exists in the read model only — exporting it and replaying it later \
         would silently destroy the configuration. Re-create the configuration, restore an earlier \
         backups/reset-*/keep-list.json into a fresh store, or pass --allow-empty-keep-list if the \
         configuration is meant to be gone",
        eventless.join(", ")
    ))
}

/// Reads every keep-list stream into an export document.
pub async fn export_keep_list(
    pool: &PgPool,
    connection: &mut MultiplexedConnection,
    database_target: &str,
    allow_empty_keep_list: bool,
) -> Result<KeepListExport, anyhow::Error> {
    let mut streams = Vec::new();
    let mut keep_rows: Vec<(AggregateCategory, i64)> = Vec::new();
    for category in keep_categories() {
        let sql = keep_id_sql(category).ok_or_else(|| {
            anyhow::anyhow!("keep category {} has no id query", category.as_str())
        })?;
        let ids: Vec<Uuid> = sqlx::query_scalar(sql).fetch_all(pool).await?;
        // Safety net (issue #770): a wrong id query would resolve no streams and
        // the export would then be replayed as "the configuration is empty" —
        // the wipe would destroy the very data this level promises to keep.
        let rows: i64 = sqlx::query_scalar(category.count_sql())
            .fetch_one(pool)
            .await?;
        ensure_streams_resolved(category, rows, ids.len())?;
        keep_rows.push((category, rows));
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
    let export = KeepListExport {
        format_version: EXPORT_FORMAT_VERSION,
        created_at: Utc::now(),
        database_target: database_target.to_string(),
        streams,
    };
    // Guard 1 (issue #810): rows in a keep projection but no events in the
    // store means the store was already lost — never export that silently.
    ensure_events_exported(&export, &keep_rows, allow_empty_keep_list)?;
    Ok(export)
}

/// The keep stream ids the projections currently resolve to (issue #810).
///
/// Used by the wipe as a second probe source: an export with **no** events must
/// not switch the empty-event-store assertion off — the projections still name
/// the streams that have to be empty.
pub async fn current_keep_streams(pool: &PgPool) -> Result<Vec<String>, anyhow::Error> {
    let mut streams = Vec::new();
    for category in keep_categories() {
        let sql = keep_id_sql(category).ok_or_else(|| {
            anyhow::anyhow!("keep category {} has no id query", category.as_str())
        })?;
        let ids: Vec<Uuid> = sqlx::query_scalar(sql).fetch_all(pool).await?;
        for id in ids {
            streams.push(stream_id(category, id));
        }
    }
    Ok(streams)
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

/// Replays an export into the **fresh** event store, one stream at a time.
///
/// Returns the number of appended events. A stream is appended in a single
/// `EMAPPEND` call so its events keep their relative order and land on the same
/// partition key as before the wipe.
///
/// Every event carries its own expected version: SierraDB runs in **strict
/// versioning mode** and rejects `EXPECTED_VERSION any` (`-INVALIDARG`), so the
/// first event of a stream is appended with `Empty` and event *n* with
/// `Exact(n - 1)`. That reproduces the original stream versions exactly, and a
/// replay into a store that is **not** empty fails loudly with a version
/// conflict instead of silently duplicating history.
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
            // Strict versioning: `Empty` for the first event, `Exact(n-1)` after
            // it (SierraDB rejects `ExpectedVersion::Any`).
            let expected = match event.stream_version {
                0 => ExpectedVersion::Empty,
                version => ExpectedVersion::Exact(version - 1),
            };
            events.push(
                EMAppendEvent::new(stream.stream_id.clone(), event.event_name.clone())
                    .event_id(event.event_id)
                    .expected_version(expected)
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
                anyhow::anyhow!(
                    "EMAPPEND {} ({} events) failed: {error} — the replay needs a FRESH event \
                     store (strict versioning rejects a stream that already has events); drop the \
                     SierraDB volume first",
                    stream.stream_id,
                    count
                )
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
    fn keep_categories_are_the_configuration_set() {
        let categories: Vec<&str> = keep_categories().map(|c| c.as_str()).collect();
        assert_eq!(
            categories,
            vec!["ai_config", "settings", "membership", "project_membership"]
        );
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

    /// Regression for the `business` E2E failure: `projection_membership` has
    /// no `id` column (its PK is `(block_id, user_id)`), so the membership keep
    /// ids are the **block** ids, deduplicated.
    #[test]
    fn membership_keep_ids_are_block_ids() {
        let sql =
            keep_id_sql(AggregateCategory::Membership).expect("membership is a keep category");
        assert!(
            sql.contains("block_id"),
            "membership must select block_id: {sql}"
        );
        assert!(sql.contains("DISTINCT"), "one stream per block: {sql}");
        assert!(
            !sql.contains("SELECT id "),
            "projection_membership has no id: {sql}"
        );
    }

    /// The project-scoped membership aggregate is keyed by its **project** id
    /// (`projection_project_membership` has the composite PK
    /// `(project_id, user_id)` and no `id` column), so the keep ids are the
    /// distinct project ids — the same reasoning as the block-scoped twin.
    #[test]
    fn project_membership_keep_ids_are_project_ids() {
        let sql = keep_id_sql(AggregateCategory::ProjectMembership)
            .expect("project_membership is a keep category");
        assert!(
            sql.contains("project_id"),
            "project_membership must select project_id: {sql}"
        );
        assert!(sql.contains("DISTINCT"), "one stream per project: {sql}");
        assert!(
            !sql.contains("SELECT id "),
            "projection_project_membership has no id: {sql}"
        );
    }

    /// A non-empty keep projection that resolves to zero streams must abort the
    /// export instead of wiping the configuration away.
    #[test]
    fn a_keep_category_with_rows_but_no_streams_refuses() {
        let error =
            ensure_streams_resolved(AggregateCategory::Settings, 1, 0).expect_err("must refuse");
        let message = error.to_string();
        assert!(message.contains("refusing to export"));
        assert!(message.contains("projection_settings"));
        assert!(
            ensure_streams_resolved(AggregateCategory::Settings, 1, 1).is_ok(),
            "a resolved stream passes"
        );
        // An empty projection is not an error: a fresh stack has no config yet.
        assert!(
            ensure_streams_resolved(AggregateCategory::Settings, 0, 0).is_ok(),
            "an empty keep projection is not an error"
        );
    }

    /// The historical shape of the 2026-11-03 loss (issue #810): the projections
    /// still hold the configuration rows, every keep stream carries `"events": []`.
    const EMPTY_KEEP_LIST_FIXTURE: &str = include_str!("fixtures/keep-list-empty-events.json");

    fn export_with_streams(streams: Vec<ExportedStream>) -> KeepListExport {
        KeepListExport {
            format_version: EXPORT_FORMAT_VERSION,
            created_at: Utc::now(),
            database_target: "localhost/breakdown".to_string(),
            streams,
        }
    }

    fn single_event_stream(category: AggregateCategory) -> ExportedStream {
        let id = Uuid::now_v7();
        ExportedStream {
            stream_id: stream_id(category, id),
            category: category.as_str().to_string(),
            events: vec![ExportedEvent {
                stream_id: stream_id(category, id),
                event_name: "KeepEvent".to_string(),
                event_id: Uuid::now_v7(),
                stream_version: 0,
                timestamp_millis: 1_700_000_000_000,
                payload_hex: String::new(),
                metadata_hex: String::new(),
            }],
        }
    }

    /// Defect 1 of issue #810: rows in a keep projection with **no** events in the
    /// store is only explainable by an already-lost event store, so the export
    /// must refuse instead of writing a keep-list that replays nothing.
    #[test]
    fn an_export_without_events_refuses_while_the_projections_hold_rows() {
        let export = export_with_streams(vec![ExportedStream {
            stream_id: "ai_config-0199a0c0-0000-7000-8000-000000000000".to_string(),
            category: "ai_config".to_string(),
            events: Vec::new(),
        }]);
        assert_eq!(export.event_count(), 0);

        let ai_config = [(AggregateCategory::AiConfig, 1)];
        let error = ensure_events_exported(&export, &ai_config, false).expect_err("must refuse");
        let message = error.to_string();
        assert!(message.contains("refusing to export"), "{message}");
        assert!(
            message.contains("ai_config: 1 row(s) / 0 events"),
            "{message}"
        );
        assert!(message.contains("--allow-empty-keep-list"), "{message}");

        // The explicit override, an empty configuration and a real export pass.
        assert!(ensure_events_exported(&export, &ai_config, true).is_ok());
        assert!(
            ensure_events_exported(&export, &[(AggregateCategory::AiConfig, 0)], false).is_ok()
        );
        let real = export_with_streams(vec![single_event_stream(AggregateCategory::Settings)]);
        assert!(ensure_events_exported(&real, &[(AggregateCategory::Settings, 1)], false).is_ok());
    }

    /// Issue #810 review: the guard must be **per category**. An eventless
    /// `ai_config` beside a non-empty `settings` passed a total-only check — the
    /// wipe then deleted the projection and the replay skipped the empty stream.
    #[test]
    fn an_eventless_keep_category_is_refused_even_when_another_one_has_events() {
        let export = export_with_streams(vec![single_event_stream(AggregateCategory::Settings)]);
        assert_eq!(export.event_count(), 1);
        let keep = [
            (AggregateCategory::AiConfig, 1),
            (AggregateCategory::Settings, 1),
        ];

        let error = ensure_events_exported(&export, &keep, false).expect_err("must refuse");
        let message = error.to_string();
        assert!(
            message.contains("ai_config: 1 row(s) / 0 events"),
            "{message}"
        );
        assert!(!message.contains("settings:"), "{message}");

        // Both categories carrying events is the healthy case.
        let healthy = export_with_streams(vec![
            single_event_stream(AggregateCategory::AiConfig),
            single_event_stream(AggregateCategory::Settings),
        ]);
        assert!(ensure_events_exported(&healthy, &keep, false).is_ok());
    }

    /// Regression fixture from the 2026-11-03 incident (10 streams, 0 events):
    /// this document must never be exported again, and replaying it restores
    /// nothing (issue #810).
    #[test]
    fn the_historical_empty_export_is_refused() {
        let export: KeepListExport =
            serde_json::from_str(EMPTY_KEEP_LIST_FIXTURE).expect("fixture parses");
        assert_eq!(export.streams.len(), 10);
        assert_eq!(export.event_count(), 0);
        assert!(
            ensure_events_exported(&export, &[(AggregateCategory::AiConfig, 1)], false).is_err()
        );
        assert!(ensure_events_exported(&export, &[(AggregateCategory::AiConfig, 1)], true).is_ok());

        let counts = export.category_counts();
        let ai_config = counts
            .iter()
            .find(|count| count.category == AggregateCategory::AiConfig)
            .expect("ai_config is in the fixture");
        assert_eq!(ai_config.streams, 1);
        assert_eq!(ai_config.events, 0);
        let membership = counts
            .iter()
            .find(|count| count.category == AggregateCategory::Membership)
            .expect("membership is in the fixture");
        assert_eq!(membership.streams, 8);
    }

    #[test]
    fn category_counts_summarize_streams_and_events_in_registry_order() {
        let export = export_with_streams(vec![
            single_event_stream(AggregateCategory::Settings),
            single_event_stream(AggregateCategory::Membership),
            single_event_stream(AggregateCategory::Membership),
        ]);
        let counts = export.category_counts();
        let rendered: Vec<(&str, usize, usize)> = counts
            .iter()
            .map(|count| (count.category.as_str(), count.streams, count.events))
            .collect();
        assert_eq!(
            rendered,
            vec![("settings", 1, 1), ("membership", 2, 2)],
            "registry order, one entry per present category"
        );
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
