// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4-flash (opencode-go)

// Crate-level lint suppression for this fixture/contract test target
// (justification, AGENTS.md §3): test code is the exempted class for the
// panic-family lints, and this suite deliberately `.expect()`s / `panic!()`s
// when a captured fixture no longer matches the live contract — the panic IS
// the drift signal. `print_stdout`/`print_stderr` back the fixture capture
// tool's `captured …` diagnostics. Narrower per-function allows would not
// change the exempted-class justification, only add noise.
#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::panic,
    clippy::print_stdout,
    clippy::print_stderr,
    clippy::dbg_macro
)]
//! Event-schema contract tests (ADR-020 D4).
//!
//! Captured event fixtures are replayed through the *current* projector
//! binaries against a real Postgres container and the projection (including
//! `projector_version`) is asserted. A captured fixture that no longer
//! deserializes, or a projector that no longer consumes a historical event
//! shape, fails CI instead of surfacing as a silent audit gap in production.
//!
//! Two tests:
//! - `captured_event_fixtures_still_deserialize` — pure serde gate (no
//!   containers): every fixture must deserialize into today's event type.
//! - `replay_captured_chain_through_projectors_round_trips` — Tier-1/2
//!   (Postgres only, no SierraDB): replays the full hierarchy chain through
//!   the projectors in one transaction and asserts each projection row,
//!   including `projector_version` (ADR-020 D4 marker).
//!
//! Fixtures live in `fixtures/events/*.json` and are frozen wire snapshots.
//! Regenerate them deliberately after a *coordinated* contract change by
//! running the ignored capture test:
//!
//! ```text
//! cargo test -p integration-tests --test event_fixture_contract_tests \
//!     capture_event_fixtures -- --ignored --nocapture
//! ```
//!
//! Regenerating is itself a MAJOR-coordination event (bump
//! `PROJECTOR_VERSION` in `crates/infra/src/projectors/mod.rs` in the same
//! change; see release-runbook.md §5).

mod fixtures;

use std::path::PathBuf;

use anyhow::{Result, anyhow, bail};
use breakdown_core::block::events::BlockEvent;
use breakdown_core::character::category::CharacterCategory;
use breakdown_core::character::events::{CharacterEvent, CharacterMeasurements, ContactInfo};
use breakdown_core::costume::events::CostumeEvent;
use breakdown_core::costume_category::events::CostumeCategoryEvent;
use breakdown_core::episode::events::EpisodeEvent;
use breakdown_core::scene::events::{SceneDetails, SceneEvent};
use breakdown_core::scene_shoot::events::SceneShootEvent;
use breakdown_core::season::events::SeasonEvent;
use breakdown_core::shared::{
    AggregateVersion, BlockId, EpisodeId, EventMetadata, LexicalSortKey, SceneShootId,
    SceneShootStatus, SeasonId, SeriesId, ShootingDayId,
};
use breakdown_core::shooting_day::events::{ShootingDayEvent, ShootingDaySource};
use chrono::{DateTime, TimeZone, Utc};
use infra::projectors::{
    BlockProjector, CharacterProjector, CostumeCategoryProjector, CostumeProjector,
    EpisodeProjector, PROJECTOR_VERSION, SceneProjector, SceneShootProjector, SeasonProjector,
    ShootingDayProjector,
};
use kameo_es::Event;
use kameo_es::event_handler::EntityEventHandler;
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use sqlx::PgPool;
use uuid::Uuid;

/// Directory holding the frozen event fixtures (committed wire snapshots).
const FIXTURES_DIR: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/fixtures/events");

// ─────────────────────────────────────────────────────────────────────────
// Fixture model
// ─────────────────────────────────────────────────────────────────────────

/// A frozen, captured event fixture (ADR-020 D4).
///
/// `event` is the event enum value exactly as serialized on the wire;
/// `aggregate_id` / `timestamp` / `stream_version` are the envelope fields
/// the projector needs; `projector_version` records the projector-binary
/// contract version that produced this capture.
#[derive(Debug, Clone, Serialize, Deserialize)]
struct EventFixture {
    event: Value,
    aggregate_id: Uuid,
    timestamp: DateTime<Utc>,
    stream_version: u64,
    projector_version: i64,
}

impl EventFixture {
    fn new<E: Serialize>(event: E, aggregate_id: Uuid, timestamp: DateTime<Utc>) -> Result<Self> {
        Ok(Self {
            event: serde_json::to_value(event)?,
            aggregate_id,
            timestamp,
            stream_version: 1,
            projector_version: PROJECTOR_VERSION,
        })
    }

    fn path(name: &str) -> PathBuf {
        PathBuf::from(FIXTURES_DIR).join(format!("{name}.json"))
    }
}

/// The full production-hierarchy sample chain (Season → … → SceneShoot),
/// with fixed deterministic ids so the captured fixtures are stable.
struct SampleChain {
    season: SeasonEvent,
    block: BlockEvent,
    episode: EpisodeEvent,
    scene: SceneEvent,
    character: CharacterEvent,
    costume: CostumeEvent,
    shooting_day: ShootingDayEvent,
    costume_category: CostumeCategoryEvent,
    scene_shoot: SceneShootEvent,
    season_id: Uuid,
    block_id: Uuid,
    episode_id: Uuid,
    scene_id: Uuid,
    character_id: Uuid,
    series_id: Uuid,
    costume_id: Uuid,
    shooting_day_id: Uuid,
    category_id: Uuid,
    scene_shoot_id: Uuid,
    timestamp: DateTime<Utc>,
}

/// Deterministic UUIDv7 fixture identifier.
///
/// Stable across runs (no `Uuid::now_v7()` — regeneration must be
/// reproducible) while carrying the RFC 9562 version-7 and RFC 4122 variant
/// bits, so the frozen fixtures use the same identifier class as production
/// entities (UUIDv7 policy, AGENTS.md §3). `tag` seeds the 12-bit `rand_a`
/// and the 62-bit `rand_b` fields.
fn fixed_uuid(tag: u64) -> Uuid {
    // Fixed epoch-ms (2026-05-28T21:46:40Z) so the version field stays valid
    // without a wall-clock dependency.
    const FIXED_TS_MS: u64 = 1_780_000_000_000;
    let rand_a = (tag & 0x0FFF) as u128;
    let rand_b = (tag as u128) & ((1u128 << 62) - 1);
    let bits = ((FIXED_TS_MS as u128) << 80)
        | (0x7u128 << 76)
        | (rand_a << 64)
        | (0b10u128 << 62)
        | rand_b;
    Uuid::from_u128(bits)
}

/// The deterministic fixture ids must be genuine UUIDv7 (RFC 9562) values.
#[test]
fn fixed_uuid_produces_uuidv7() {
    for tag in 1..=12u64 {
        let id = fixed_uuid(tag);
        assert_eq!(id.get_version(), Some(uuid::Version::SortRand), "tag {tag}");
        assert_eq!(id.get_variant(), uuid::Variant::RFC4122, "tag {tag}");
    }
}

fn sample_chain() -> SampleChain {
    let timestamp = Utc.with_ymd_and_hms(2026, 8, 6, 9, 0, 0).unwrap();
    let season_id = fixed_uuid(1);
    let block_id = fixed_uuid(2);
    let episode_id = fixed_uuid(3);
    let scene_id = fixed_uuid(4);
    let character_id = fixed_uuid(5);
    let costume_id = fixed_uuid(6);
    let shooting_day_id = fixed_uuid(7);
    let category_id = fixed_uuid(8);
    let scene_shoot_id = fixed_uuid(9);
    let series_id = SeriesId(fixed_uuid(10));

    SampleChain {
        season: SeasonEvent::SeasonCreated {
            id: season_id,
            series_id,
            number: 1,
            title: Some("Staffel 1".to_string()),
            version: AggregateVersion(1),
        },
        block: BlockEvent::BlockCreated {
            id: block_id,
            season_id: SeasonId(season_id),
            series_id,
            number: 1,
            start_date: None,
            end_date: None,
            version: AggregateVersion(1),
        },
        episode: EpisodeEvent::EpisodeCreated {
            id: episode_id,
            block_id: BlockId(block_id),
            series_id,
            number: 1,
            name: Some("Block 1 Episode 1".to_string()),
            version: AggregateVersion(1),
        },
        scene: SceneEvent::SceneCreated {
            id: scene_id,
            episode_id: EpisodeId(episode_id),
            details: SceneDetails {
                scene_number: Some(1),
                location: Some("Set A".to_string()),
                mood: Some("Tag".to_string()),
                is_schedule_set: false,
                summary: Some("Eröffnungsszene".to_string()),
                script_day: Some("1. Spieltag".to_string()),
            },
            assigned_characters: vec![],
            version: AggregateVersion(1),
        },
        character: CharacterEvent::CharacterCreated {
            id: character_id,
            season_id: SeasonId(season_id),
            name: "Hauptrolle".to_string(),
            category: CharacterCategory::MainCast,
            measurements: CharacterMeasurements {
                shoe_size: None,
                hat_size: None,
                height: None,
                weight: None,
                chest: None,
                waist: None,
                hips: None,
            },
            contact_info: ContactInfo {
                phone: Some("+49 000".to_string()),
                email: None,
            },
            version: AggregateVersion(1),
        },
        costume: CostumeEvent::CostumeCreated {
            id: costume_id,
            character_id: Some(character_id),
            notes: "Rote Lederjacke".to_string(),
            details: vec![],
            photos: vec![],
            version: AggregateVersion(1),
        },
        shooting_day: ShootingDayEvent::ShootingDayCreated {
            id: ShootingDayId(shooting_day_id),
            episode_id: EpisodeId(episode_id),
            label: Some("Drehtag 1".to_string()),
            order_key: LexicalSortKey::from_static("!a"),
            date: None,
            source: ShootingDaySource::Manual,
            version: AggregateVersion(1),
        },
        costume_category: CostumeCategoryEvent::CostumeCategoryCreated {
            id: category_id,
            season_id: SeasonId(season_id),
            name: "Oberteil".to_string(),
            order_key: LexicalSortKey::from_static("!b"),
            version: AggregateVersion(1),
        },
        scene_shoot: SceneShootEvent::SceneShootPlanned {
            id: SceneShootId(scene_shoot_id),
            scene_id,
            shooting_day_id: ShootingDayId(shooting_day_id),
            planned_order: LexicalSortKey::from_static("!c"),
            status: SceneShootStatus::Planned,
            version: AggregateVersion(1),
        },
        season_id,
        block_id,
        episode_id,
        scene_id,
        character_id,
        series_id: series_id.0,
        costume_id,
        shooting_day_id,
        category_id,
        scene_shoot_id,
        timestamp,
    }
}

fn sample_fixtures(chain: &SampleChain) -> Result<Vec<(&'static str, EventFixture)>> {
    let t = chain.timestamp;
    Ok(vec![
        (
            "season_created",
            EventFixture::new(chain.season.clone(), chain.season_id, t)?,
        ),
        (
            "block_created",
            EventFixture::new(chain.block.clone(), chain.block_id, t)?,
        ),
        (
            "episode_created",
            EventFixture::new(chain.episode.clone(), chain.episode_id, t)?,
        ),
        (
            "scene_created",
            EventFixture::new(chain.scene.clone(), chain.scene_id, t)?,
        ),
        (
            "character_created",
            EventFixture::new(chain.character.clone(), chain.character_id, t)?,
        ),
        (
            "costume_created",
            EventFixture::new(chain.costume.clone(), chain.costume_id, t)?,
        ),
        (
            "shooting_day_created",
            EventFixture::new(chain.shooting_day.clone(), chain.shooting_day_id, t)?,
        ),
        (
            "costume_category_created",
            EventFixture::new(chain.costume_category.clone(), chain.category_id, t)?,
        ),
        (
            "scene_shoot_planned",
            EventFixture::new(chain.scene_shoot.clone(), chain.scene_shoot_id, t)?,
        ),
    ])
}

// ─────────────────────────────────────────────────────────────────────────
// Capture (ignored): regenerate the frozen fixtures on purpose
// ─────────────────────────────────────────────────────────────────────────

/// Regenerate `fixtures/events/*.json` from the current event types.
///
/// This is a deliberate, coordinated act (ADR-020 D4 / release-runbook §5):
/// bump `PROJECTOR_VERSION` in the same change and ship the projector
/// redeploy before old event shapes are retired.
#[test]
#[ignore = "fixture regeneration is a deliberate MAJOR-coordination act"]
fn capture_event_fixtures() {
    let chain = sample_chain();
    let fixtures = sample_fixtures(&chain).expect("sample fixtures serialize");
    std::fs::create_dir_all(FIXTURES_DIR).expect("fixture dir must be creatable");
    for (name, fixture) in fixtures {
        let json = serde_json::to_string_pretty(&fixture).expect("fixture must serialize");
        let path = EventFixture::path(name);
        std::fs::write(&path, json).expect("fixture must be writable");
        println!("captured {}", path.display());
    }
}

// ─────────────────────────────────────────────────────────────────────────
// Part A: pure serde gate — captured fixtures must still deserialize
// ─────────────────────────────────────────────────────────────────────────

/// Every captured fixture must deserialize into today's event type. A removed
/// field, retyped variant, or renamed enum variant fails here (MAJOR,
/// ADR-020 D4) — the signal that the event contract has drifted.
#[test]
fn captured_event_fixtures_still_deserialize() {
    let chain = sample_chain();
    let fixtures = sample_fixtures(&chain).expect("sample fixtures serialize");
    assert!(
        !fixtures.is_empty(),
        "fixture set must not be empty — the contract gate would be vacuous"
    );

    for (name, _) in &fixtures {
        let path = EventFixture::path(name);
        let on_disk: EventFixture =
            serde_json::from_str(&std::fs::read_to_string(&path).unwrap_or_else(|e| {
                panic!(
                    "missing fixture {}: {e} — run `capture_event_fixtures`",
                    path.display()
                )
            }))
            .expect("fixture must parse");
        // The current projector binary must support every archived fixture
        // version (ADR-020 D4): a fixture captured by a NEWER projector
        // (version > current) would be unreadable by the deployed binary —
        // a deploy-order failure.
        assert!(
            on_disk.projector_version <= PROJECTOR_VERSION,
            "{name}: fixture was captured by projector_version {} but the \
             current binary only supports {PROJECTOR_VERSION} — deploy-order \
             drift (release-runbook §5)",
            on_disk.projector_version
        );
        // The serde gate: deserialize the wire snapshot into the current type.
        let _: () = match *name {
            "season_created" => {
                serde_json::from_value::<SeasonEvent>(on_disk.event.clone()).expect("SeasonEvent");
            }
            "block_created" => {
                serde_json::from_value::<BlockEvent>(on_disk.event.clone()).expect("BlockEvent");
            }
            "episode_created" => {
                serde_json::from_value::<EpisodeEvent>(on_disk.event.clone())
                    .expect("EpisodeEvent");
            }
            "scene_created" => {
                serde_json::from_value::<SceneEvent>(on_disk.event.clone()).expect("SceneEvent");
            }
            "character_created" => {
                serde_json::from_value::<CharacterEvent>(on_disk.event.clone())
                    .expect("CharacterEvent");
            }
            "costume_created" => {
                serde_json::from_value::<CostumeEvent>(on_disk.event.clone())
                    .expect("CostumeEvent");
            }
            "shooting_day_created" => {
                serde_json::from_value::<ShootingDayEvent>(on_disk.event.clone())
                    .expect("ShootingDayEvent");
            }
            "costume_category_created" => {
                serde_json::from_value::<CostumeCategoryEvent>(on_disk.event.clone())
                    .expect("CostumeCategoryEvent");
            }
            "scene_shoot_planned" => {
                serde_json::from_value::<SceneShootEvent>(on_disk.event.clone())
                    .expect("SceneShootEvent");
            }
            other => panic!("unhandled fixture {other}"),
        };
    }
}

// ─────────────────────────────────────────────────────────────────────────
// Part B: projector replay (Postgres-only tier) — the current projector
// binary still consumes the captured fixtures and stamps projector_version
// ─────────────────────────────────────────────────────────────────────────

fn event_of<E, M>(fixture: &EventFixture) -> Event<E, M>
where
    E: serde::de::DeserializeOwned,
    M: serde::de::DeserializeOwned + Default,
{
    let data: E = serde_json::from_value(fixture.event.clone()).expect("event must deserialize");
    Event {
        id: Uuid::now_v7(),
        partition_key: Uuid::now_v7(),
        partition_id: 0,
        transaction_id: Uuid::now_v7(),
        partition_sequence: fixture.stream_version,
        stream_version: fixture.stream_version,
        stream_id: kameo_es::StreamId::new(format!("fixture-{}", fixture.aggregate_id)),
        name: "captured-fixture".to_string(),
        data,
        metadata: kameo_es::Metadata {
            causation_command: None,
            causation_event: None,
            data: Some(M::default()),
        },
        timestamp: fixture.timestamp,
    }
}

/// Replay the whole captured chain through the current projectors in one
/// transaction (FK parents first), then assert every projection row — with
/// the `projector_version` marker (ADR-020 D4).
#[tokio::test]
async fn replay_captured_chain_through_projectors_round_trips() -> Result<()> {
    let (pool, _pg) = fixtures::spawn_postgres().await?;
    let chain = sample_chain();
    // Replay the ARCHIVED on-disk fixtures — never freshly serialized
    // sample_chain() events — so the projectors are exercised against the
    // historical wire payloads exactly as captured.
    let by_name = |n: &str| -> EventFixture {
        let path = EventFixture::path(n);
        serde_json::from_str(&std::fs::read_to_string(&path).unwrap_or_else(|e| {
            panic!(
                "missing fixture {}: {e} — run `capture_event_fixtures`",
                path.display()
            )
        }))
        .expect("fixture must parse")
    };

    let mut tx = pool.begin().await?;

    // Dependency order: season → block → episode → scene → character →
    // costume → shooting_day → costume_category → scene_shoot (FK chain).
    let mut season = SeasonProjector;
    season
        .handle(
            &mut tx,
            chain.season_id,
            event_of::<SeasonEvent, EventMetadata>(&by_name("season_created")),
        )
        .await?;
    let mut block = BlockProjector;
    block
        .handle(
            &mut tx,
            chain.block_id,
            event_of::<BlockEvent, EventMetadata>(&by_name("block_created")),
        )
        .await?;
    let mut episode = EpisodeProjector;
    episode
        .handle(
            &mut tx,
            chain.episode_id,
            event_of::<EpisodeEvent, EventMetadata>(&by_name("episode_created")),
        )
        .await?;
    let mut scene = SceneProjector;
    scene
        .handle(
            &mut tx,
            chain.scene_id,
            event_of::<SceneEvent, EventMetadata>(&by_name("scene_created")),
        )
        .await?;
    let mut character = CharacterProjector;
    character
        .handle(
            &mut tx,
            chain.character_id,
            event_of::<CharacterEvent, EventMetadata>(&by_name("character_created")),
        )
        .await?;
    let mut costume = CostumeProjector;
    costume
        .handle(
            &mut tx,
            chain.costume_id,
            event_of::<CostumeEvent, EventMetadata>(&by_name("costume_created")),
        )
        .await?;
    let mut shooting_day = ShootingDayProjector;
    shooting_day
        .handle(
            &mut tx,
            ShootingDayId(chain.shooting_day_id),
            event_of::<ShootingDayEvent, EventMetadata>(&by_name("shooting_day_created")),
        )
        .await?;
    let mut costume_category = CostumeCategoryProjector;
    costume_category
        .handle(
            &mut tx,
            chain.category_id,
            event_of::<CostumeCategoryEvent, EventMetadata>(&by_name("costume_category_created")),
        )
        .await?;
    let mut scene_shoot = SceneShootProjector;
    scene_shoot
        .handle(
            &mut tx,
            SceneShootId(chain.scene_shoot_id),
            event_of::<SceneShootEvent, EventMetadata>(&by_name("scene_shoot_planned")),
        )
        .await?;

    tx.commit().await?;

    // Assertions (ADR-020 D4 contract): every projection row must equal the
    // fixture-derived expected state — the complete projected row as JSON
    // (timestamptz columns excluded; compared separately with bound typed
    // values, timezone-safe) plus the `projector_version` marker. Each SQL
    // statement below is a static literal (static-SQL rule, AGENTS.md).
    assert_projected(
        &pool,
        "SELECT to_jsonb(projection_season) - 'updated_at' FROM projection_season WHERE id = $1",
        "SELECT (updated_at = $1) FROM projection_season WHERE id = $2",
        chain.season_id,
        json!({
            "id": chain.season_id,
            "series_id": chain.series_id,
            "number": 1,
            "title": "Staffel 1",
            "version": 1,
            "projector_version": PROJECTOR_VERSION,
        }),
        chain.timestamp,
    )
    .await?;
    assert_projected(
        &pool,
        "SELECT to_jsonb(projection_block) - 'updated_at' FROM projection_block WHERE id = $1",
        "SELECT (updated_at = $1) FROM projection_block WHERE id = $2",
        chain.block_id,
        json!({
            "id": chain.block_id,
            "season_id": chain.season_id,
            "series_id": chain.series_id,
            "number": 1,
            "start_date": null,
            "end_date": null,
            "version": 1,
            "projector_version": PROJECTOR_VERSION,
        }),
        chain.timestamp,
    )
    .await?;
    assert_projected(
        &pool,
        "SELECT to_jsonb(projection_episode) - 'updated_at' FROM projection_episode WHERE id = $1",
        "SELECT (updated_at = $1) FROM projection_episode WHERE id = $2",
        chain.episode_id,
        json!({
            "id": chain.episode_id,
            "block_id": chain.block_id,
            "series_id": chain.series_id,
            "number": 1,
            "name": "Block 1 Episode 1",
            "version": 1,
            "projector_version": PROJECTOR_VERSION,
        }),
        chain.timestamp,
    )
    .await?;
    assert_projected(
        &pool,
        "SELECT to_jsonb(projection_scene) - 'updated_at' FROM projection_scene WHERE id = $1",
        "SELECT (updated_at = $1) FROM projection_scene WHERE id = $2",
        chain.scene_id,
        json!({
            "id": chain.scene_id,
            "episode_id": chain.episode_id,
            "scene_number": 1,
            "location": "Set A",
            "mood": "Tag",
            "is_schedule_set": false,
            "summary": "Eröffnungsszene",
            "script_day": "1. Spieltag",
            "version": 1,
            "projector_version": PROJECTOR_VERSION,
        }),
        chain.timestamp,
    )
    .await?;
    assert_projected(
        &pool,
        "SELECT to_jsonb(projection_character) - 'updated_at' FROM projection_character WHERE id = $1",
        "SELECT (updated_at = $1) FROM projection_character WHERE id = $2",
        chain.character_id,
        json!({
            "id": chain.character_id,
            "season_id": chain.season_id,
            "name": "Hauptrolle",
            "category": "main_cast",
            "measurements": {
                "chest": null, "hat_size": null, "height": null, "hips": null,
                "shoe_size": null, "waist": null, "weight": null,
            },
            "contact": { "phone": "+49 000", "email": null },
            "version": 1,
            "projector_version": PROJECTOR_VERSION,
        }),
        chain.timestamp,
    )
    .await?;
    assert_projected(
        &pool,
        "SELECT to_jsonb(projection_costume) - 'updated_at' FROM projection_costume WHERE id = $1",
        "SELECT (updated_at = $1) FROM projection_costume WHERE id = $2",
        chain.costume_id,
        json!({
            "id": chain.costume_id,
            "character_id": chain.character_id,
            "notes": "Rote Lederjacke",
            "version": 1,
            "projector_version": PROJECTOR_VERSION,
        }),
        chain.timestamp,
    )
    .await?;
    assert_projected(
        &pool,
        "SELECT to_jsonb(projection_shooting_day) - 'updated_at' - 'wrapped_at' \
         FROM projection_shooting_day WHERE id = $1",
        "SELECT (updated_at = $1 AND wrapped_at IS NULL) \
         FROM projection_shooting_day WHERE id = $2",
        chain.shooting_day_id,
        json!({
            "id": chain.shooting_day_id,
            "episode_id": chain.episode_id,
            "label": "Drehtag 1",
            "order_key": "!a",
            "date": null,
            "source": "Manual",
            "archived": false,
            "version": 1,
            "projector_version": PROJECTOR_VERSION,
        }),
        chain.timestamp,
    )
    .await?;
    assert_projected(
        &pool,
        "SELECT to_jsonb(projection_costume_category) - 'updated_at' \
         FROM projection_costume_category WHERE id = $1",
        "SELECT (updated_at = $1) FROM projection_costume_category WHERE id = $2",
        chain.category_id,
        json!({
            "id": chain.category_id,
            "season_id": chain.season_id,
            "name": "Oberteil",
            "order_key": "!b",
            "archived": false,
            "version": 1,
            "projector_version": PROJECTOR_VERSION,
        }),
        chain.timestamp,
    )
    .await?;
    assert_projected(
        &pool,
        "SELECT to_jsonb(projection_scene_shoot) - 'updated_at' - 'start_dt' - 'end_dt' - 'created_at' \
         FROM projection_scene_shoot WHERE id = $1",
        "SELECT (updated_at = $1 AND start_dt IS NULL AND end_dt IS NULL) \
         FROM projection_scene_shoot WHERE id = $2",
        chain.scene_shoot_id,
        json!({
            "id": chain.scene_shoot_id,
            "scene_id": chain.scene_id,
            "shooting_day_id": chain.shooting_day_id,
            "planned_order": "!c",
            "actual_order": null,
            "status": "Planned",
            "notes": [],
            "continuity_photo_ids": [],
            "version": 1,
            "projector_version": PROJECTOR_VERSION,
        }),
        chain.timestamp,
    )
    .await?;

    Ok(())
}

/// Assert that a projection row equals the fixture-derived expected state.
///
/// `row_query` is a static SQL literal returning the row as `to_jsonb(...)`
/// with the timestamptz columns removed (their representation depends on the
/// session timezone); `tz_query` is a static SQL literal asserting the
/// timestamptz columns against the bound fixture timestamp (timezone-safe).
/// Every projected domain column is compared — a dropped or mis-mapped field
/// fails the contract test, not just the marker.
async fn assert_projected(
    pool: &PgPool,
    row_query: &'static str,
    tz_query: &'static str,
    id: Uuid,
    expected: Value,
    timestamp: DateTime<Utc>,
) -> Result<()> {
    let row: sqlx::types::Json<Value> = sqlx::query_scalar(row_query)
        .bind(id)
        .fetch_one(pool)
        .await
        .map_err(|e| anyhow!("projection row for {row_query:?} missing: {e}"))?;
    if row.0 != expected {
        bail!(
            "projection row for {row_query:?} no longer matches the fixture:\n  got:      {}\n  expected: {}",
            serde_json::to_string_pretty(&row.0).unwrap_or_else(|_| "<unprintable>".to_string()),
            serde_json::to_string_pretty(&expected).unwrap_or_else(|_| "<unprintable>".to_string()),
        );
    }
    let timestamps_ok: bool = sqlx::query_scalar(tz_query)
        .bind(timestamp)
        .bind(id)
        .fetch_one(pool)
        .await
        .map_err(|e| anyhow!("timestamptz check for {tz_query:?} failed: {e}"))?;
    if !timestamps_ok {
        bail!(
            "timestamptz columns of the row for {row_query:?} do not match the fixture \
             timestamp {timestamp:?}"
        );
    }
    Ok(())
}
