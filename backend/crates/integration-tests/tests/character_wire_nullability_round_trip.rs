// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: omen-alpha (opencode-go)

#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::panic,
    clippy::print_stdout,
    clippy::print_stderr,
    clippy::dbg_macro
)]
//! Tier-4 round-trip test for the issue-#423 nullability lie.
//!
//! The Flutter client could not deserialize ANY `CharacterView` whose
//! measurements were unset — i.e. every freshly created character. The wire
//! payload (reproduced from the issue report):
//!
//! ```json
//! {"measurements":{"shoe_size":null,"hat_size":null,"height":null,
//!  "weight":null,"chest":null,"waist":null,"hips":null}, ...}
//! ```
//!
//! This test drives the real chain `CharacterCreated (unset measurements)
//! → SierraDB EAPPEND → CharacterProjector → projection_character →
//! CharacterRepository` and then asserts the **serde wire shape** of the
//! resulting `CharacterView`: unset measurements must serialize as JSON
//! `null` and deserialize back cleanly — the exact payload shape the
//! generated Dart client previously threw on (`null as String` against a
//! non-nullable contract).
//!
//! Note (issue #423, re issue #25): this test drives the read path through
//! the real projector, not a bypassed `CommandService` — the projection row
//! is what the handler serves.

mod fixtures;

use std::sync::Arc;
use std::time::Duration;

use anyhow::{Result, anyhow};
use chrono::Utc;
use redis::Client as RedisClient;
use uuid::Uuid;

use breakdown_core::character::category::CharacterCategory;
use breakdown_core::character::events::{CharacterMeasurements, ContactInfo};
use breakdown_core::character::ports::CharacterRepository as _;
use breakdown_core::character::views::CharacterView;
use breakdown_core::shared::{AggregateVersion, SeasonId};

const PROJECTION_DEADLINE: Duration = Duration::from_secs(15);
const POLL_INTERVAL: Duration = Duration::from_millis(150);

/// CBOR-encode + EAPPEND an event into SierraDB (same encoding path the
/// kameo_es PostgresProcessor reads).
async fn eappend_event<T: serde::Serialize>(
    client: &Arc<RedisClient>,
    stream_id: &str,
    event_name: &str,
    expected_version: &str,
    payload: &T,
) -> Result<()> {
    let mut conn = client.get_multiplexed_async_connection().await?;
    let mut encoded = Vec::new();
    ciborium::into_writer(payload, &mut encoded).map_err(|e| anyhow!("CBOR encode failed: {e}"))?;
    let now_ms = Utc::now().timestamp_millis().try_into().unwrap_or(0u64);
    let _resp: redis::Value = redis::cmd("EAPPEND")
        .arg(stream_id)
        .arg(event_name)
        .arg("EXPECTED_VERSION")
        .arg(expected_version)
        .arg("PAYLOAD")
        .arg(&encoded)
        .arg("TIMESTAMP")
        .arg(now_ms.to_string().as_bytes())
        .query_async(&mut conn)
        .await
        .map_err(|e| anyhow!("EAPPEND {event_name} failed: {e}"))?;
    Ok(())
}

/// Wait until `projection_character` carries `id` at `min_version`.
async fn await_character_version(pool: &sqlx::PgPool, id: Uuid, min_version: i64) -> Result<()> {
    let deadline = std::time::Instant::now() + PROJECTION_DEADLINE;
    loop {
        tokio::time::sleep(POLL_INTERVAL).await;
        if std::time::Instant::now() > deadline {
            anyhow::bail!("projection_character not projected within {PROJECTION_DEADLINE:?}");
        }
        let version: Option<i64> =
            sqlx::query_scalar("SELECT version FROM projection_character WHERE id = $1")
                .bind(id)
                .fetch_optional(pool)
                .await
                .map_err(|e| anyhow!("poll projection_character: {e}"))?;
        if version.is_some_and(|v| v >= min_version) {
            return Ok(());
        }
    }
}

#[tokio::test]
async fn unset_measurements_round_trip_the_wire_as_null() -> Result<()> {
    let (pool, _pg) = fixtures::spawn_postgres().await?;
    let (redis_client, _sierra_conn, _sierra) = fixtures::spawn_sierradb().await?;

    let _char_ref = infra::projectors::spawn_character_projector(
        pool.clone(),
        Arc::clone(&redis_client),
        infra::projectors::ProjectorFlushConfig::test_profile(),
    )
    .await?;

    let repo = infra::queries::CharacterRepositoryImpl::new(pool.clone());

    let char_id = Uuid::now_v7();
    let season_id = SeasonId::new();

    // A freshly created character: every measurement + contact field unset
    // (the state the device-testing session in issue #423 reproduced).
    eappend_event(
        &redis_client,
        &format!("character-{char_id}"),
        "CharacterCreated",
        "EMPTY",
        &breakdown_core::character::events::CharacterEvent::CharacterCreated {
            id: char_id,
            season_id,
            name: "Didi".into(),
            category: CharacterCategory::MainCast,
            measurements: Default::default(),
            contact_info: Default::default(),
            version: AggregateVersion::INITIAL,
        },
    )
    .await?;

    await_character_version(&pool, char_id, 1).await?;

    // Both read paths the handlers serve (`get_character`, `list_characters`).
    let view = repo.find_by_id(char_id).await?;
    let listed = repo.list_by_season(season_id, 100, 0).await?;
    assert!(
        listed.iter().any(|c| c.id == char_id),
        "character missing from list_by_season projection read"
    );

    assert_unset_wire_shape(&view)?;

    // The measurement/contact payload objects must also deserialize back —
    // `CharacterMeasurements`/`ContactInfo` derive `Deserialize` and are
    // exactly the payload structs the generated Dart client mirrors.
    let json = serde_json::to_value(&view).expect("CharacterView serializes");
    let measurements: CharacterMeasurements =
        serde_json::from_value(json["measurements"].clone()).expect("measurements deserialize");
    assert!(measurements.shoe_size.is_none());
    let contact: ContactInfo =
        serde_json::from_value(json["contact"].clone()).expect("contact deserialize");
    assert!(contact.phone.is_none());

    Ok(())
}

#[tokio::test]
async fn set_measurements_round_trip_the_wire_as_strings() -> Result<()> {
    let (pool, _pg) = fixtures::spawn_postgres().await?;
    let (redis_client, _sierra_conn, _sierra) = fixtures::spawn_sierradb().await?;

    let _char_ref = infra::projectors::spawn_character_projector(
        pool.clone(),
        Arc::clone(&redis_client),
        infra::projectors::ProjectorFlushConfig::test_profile(),
    )
    .await?;

    let repo = infra::queries::CharacterRepositoryImpl::new(pool.clone());

    let char_id = Uuid::now_v7();
    let season_id = SeasonId::new();

    eappend_event(
        &redis_client,
        &format!("character-{char_id}"),
        "CharacterCreated",
        "EMPTY",
        &breakdown_core::character::events::CharacterEvent::CharacterCreated {
            id: char_id,
            season_id,
            name: "Hero".into(),
            category: CharacterCategory::MainCast,
            measurements: Default::default(),
            contact_info: Default::default(),
            version: AggregateVersion::INITIAL,
        },
    )
    .await?;

    let meas = breakdown_core::character::events::CharacterMeasurements {
        height: Some(rust_decimal::Decimal::from(180)),
        weight: Some(rust_decimal::Decimal::from(75)),
        ..Default::default()
    };
    eappend_event(
        &redis_client,
        &format!("character-{char_id}"),
        "MeasurementsUpdated",
        "0",
        &breakdown_core::character::events::CharacterEvent::MeasurementsUpdated {
            id: char_id,
            measurements: meas,
            version: AggregateVersion(2),
        },
    )
    .await?;

    await_character_version(&pool, char_id, 2).await?;

    let view = repo.find_by_id(char_id).await?;
    assert_eq!(
        view.measurements.height.as_ref(),
        Some(&rust_decimal::Decimal::from(180))
    );
    assert_eq!(
        view.measurements.weight.as_ref(),
        Some(&rust_decimal::Decimal::from(75))
    );
    assert!(view.measurements.shoe_size.is_none());

    // Set values serialize as JSON strings (Decimal renders as a numeric
    // string) and the object still round-trips.
    let json = serde_json::to_value(&view).expect("CharacterView serializes");
    let measurements = json
        .get("measurements")
        .and_then(|m| m.as_object())
        .expect("measurements object");
    assert_eq!(
        measurements.get("height"),
        Some(&serde_json::Value::String("180".to_string())),
        "set measurement must serialize as a string on the wire"
    );
    let back: CharacterMeasurements =
        serde_json::from_value(json["measurements"].clone()).expect("round-trip deserialize");
    assert_eq!(back.height, Some(rust_decimal::Decimal::from(180)));

    Ok(())
}

/// Assert the exact issue-#423 wire shape: all seven measurements and both
/// contact fields serialize as explicit JSON `null`s.
fn assert_unset_wire_shape(view: &CharacterView) -> Result<()> {
    for (field, value) in [
        ("shoe_size", &view.measurements.shoe_size),
        ("hat_size", &view.measurements.hat_size),
        ("height", &view.measurements.height),
        ("weight", &view.measurements.weight),
        ("chest", &view.measurements.chest),
        ("waist", &view.measurements.waist),
        ("hips", &view.measurements.hips),
    ] {
        assert!(
            value.is_none(),
            "field `{field}` unexpectedly set on a fresh character"
        );
    }

    let json = serde_json::to_value(view).expect("CharacterView serializes");
    let measurements = json
        .get("measurements")
        .and_then(|m| m.as_object())
        .ok_or_else(|| anyhow!("wire payload must carry a `measurements` object"))?;
    for field in [
        "shoe_size",
        "hat_size",
        "height",
        "weight",
        "chest",
        "waist",
        "hips",
    ] {
        assert_eq!(
            measurements.get(field),
            Some(&serde_json::Value::Null),
            "wire payload for `{field}` must be JSON null — this is the exact \
             shape that broke the generated Dart client (issue #423)"
        );
    }
    let contact = json
        .get("contact")
        .and_then(|c| c.as_object())
        .ok_or_else(|| anyhow!("wire payload must carry a `contact` object"))?;
    assert_eq!(contact.get("phone"), Some(&serde_json::Value::Null));
    assert_eq!(contact.get("email"), Some(&serde_json::Value::Null));
    Ok(())
}
