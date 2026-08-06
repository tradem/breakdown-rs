// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.2 (neuralwatt)

#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::panic,
    clippy::print_stdout,
    clippy::print_stderr,
    clippy::dbg_macro
)]
//! Wire-contract fixture tests (ADR-021 D5/D6).
//!
//! Every `/v{n}` read route responds with a flat, serde-serialized DTO. A
//! frozen JSON snapshot per DTO is committed in `fixtures/wire/`; this gate
//! asserts the live serialization still matches it byte-for-byte, modulo an
//! explicit allowlist of known additive fields (ADR-021 D6).
//!
//! - A **removed** field, a **retyped** field, or a **changed value**
//!   (including a shifted `serde` default — ADR-021 D5) is a hard failure:
//!   MAJOR, new `/v{n+1}` path version.
//! - A **new** field is a failure unless it is declared in the per-DTO
//!   additive allowlist below (a field older clients tolerate because it is
//!   `#[serde(default)]`-backed and default-identical — MINOR).
//!
//! Regenerating fixtures is a deliberate act: run the ignored capture test
//! only after the ADR-021 classification has been made (and, for MAJOR
//! changes, in the same change that ships `/v{n+1}`):
//!
//! ```text
//! cargo test -p integration-tests --test wire_contract_fixture_tests \
//!     capture_wire_fixtures -- --ignored --nocapture
//! ```

use std::collections::BTreeSet;
use std::path::PathBuf;

use anyhow::{Result, bail};
use breakdown_core::block::views::BlockView;
use breakdown_core::character::category::CharacterCategory;
use breakdown_core::character::events::{CharacterMeasurements, ContactInfo};
use breakdown_core::character::views::CharacterView;
use breakdown_core::costume::views::{CostumeDetailView, CostumeView};
use breakdown_core::costume_category::views::CostumeCategoryView;
use breakdown_core::episode::views::EpisodeView;
use breakdown_core::membership::Role;
use breakdown_core::membership::views::{MembershipStateKind, MembershipView};
use breakdown_core::scene::views::SceneView;
use breakdown_core::season::views::SeasonView;
use breakdown_core::shared::{
    AggregateVersion, BlockId, EpisodeId, LexicalSortKey, SeasonId, SeriesId, ShootingDayId, UserId,
};
use breakdown_core::shooting_day::events::ShootingDaySource;
use breakdown_core::shooting_day::views::ShootingDayView;
use chrono::{DateTime, TimeZone, Utc};
use serde::Serialize;
use serde_json::Value;

/// Directory holding the frozen wire snapshots.
const FIXTURES_DIR: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/fixtures/wire");

/// Per-DTO allowlist of *additive* fields the fixture predates.
///
/// A key listed here may appear in the live serialization without being in
/// the frozen fixture (older clients tolerate it: `#[serde(default)]` and
/// default-identical to prior behaviour — MINOR, ADR-021 D3/D5). Anything
/// else that is new, removed, or changed is a hard MAJOR failure.
const ADDITIVE_ALLOWLIST: &[(&str, &str)] = &[];

/// Deterministic, version-agnostic test ids (fixtures must be stable).
fn fixed_uuid(tag: u64) -> uuid::Uuid {
    uuid::Uuid::from_u128(((tag as u128) << 64) | 0x0000_0000_0000_0001)
}

/// A representative sample of every wire DTO backing the `/v1` read routes,
/// frozen as JSON snapshots (ADR-021 D6).
fn sample_views() -> Vec<(&'static str, Value)> {
    let t: DateTime<Utc> = Utc.with_ymd_and_hms(2026, 8, 6, 9, 0, 0).unwrap();
    let season_id = fixed_uuid(1);
    let block_id = fixed_uuid(2);
    let episode_id = fixed_uuid(3);
    let scene_id = fixed_uuid(4);
    let character_id = fixed_uuid(5);
    let costume_id = fixed_uuid(6);
    let shooting_day_id = fixed_uuid(7);
    let category_id = fixed_uuid(8);
    let user_id = UserId::from_sub("user-1");

    fn snapshot<V: Serialize>(name: &'static str, view: &V) -> (&'static str, Value) {
        (
            name,
            serde_json::to_value(view).expect("view must serialize"),
        )
    }

    vec![
        snapshot(
            "season_view",
            &SeasonView {
                id: season_id,
                series_id: SeriesId(fixed_uuid(10)),
                number: 1,
                title: Some("Staffel 1".to_string()),
                version: AggregateVersion(3),
                updated_at: t,
            },
        ),
        snapshot(
            "block_view",
            &BlockView {
                id: block_id,
                season_id: SeasonId(season_id),
                series_id: SeriesId(fixed_uuid(10)),
                number: 1,
                start_date: None,
                end_date: None,
                version: AggregateVersion(2),
                updated_at: t,
            },
        ),
        snapshot(
            "episode_view",
            &EpisodeView {
                id: episode_id,
                block_id: BlockId(block_id),
                series_id: SeriesId(fixed_uuid(10)),
                number: 1,
                name: Some("Episode 1".to_string()),
                version: AggregateVersion(1),
                updated_at: t,
            },
        ),
        snapshot(
            "scene_view",
            &SceneView {
                id: scene_id,
                episode_id: EpisodeId(episode_id),
                scene_number: Some(1),
                location: Some("Set A".to_string()),
                mood: Some("Tag".to_string()),
                is_schedule_set: true,
                summary: Some("Eröffnungsszene".to_string()),
                script_day: Some("1. Spieltag".to_string()),
                shooting_day_ids: vec![ShootingDayId(shooting_day_id)],
                assigned_characters: vec![character_id],
                version: AggregateVersion(4),
                updated_at: t,
            },
        ),
        snapshot(
            "character_view",
            &CharacterView {
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
                contact: ContactInfo {
                    phone: Some("+49 000".to_string()),
                    email: None,
                },
                version: AggregateVersion(1),
                updated_at: t,
            },
        ),
        snapshot(
            "costume_view",
            &CostumeView {
                id: costume_id,
                character_id: Some(character_id),
                notes: "Rote Lederjacke".to_string(),
                details: vec![CostumeDetailView {
                    id: fixed_uuid(9),
                    subject: Some("Jacke".to_string()),
                    category_id: None,
                    category_name: None,
                    text: "Rote Lederjacke".to_string(),
                }],
                photos: vec![],
                version: AggregateVersion(2),
                updated_at: t,
            },
        ),
        snapshot(
            "shooting_day_view",
            &ShootingDayView {
                id: ShootingDayId(shooting_day_id),
                episode_id: EpisodeId(episode_id),
                label: Some("Drehtag 1".to_string()),
                order_key: LexicalSortKey::from_static("!a"),
                date: None,
                source: ShootingDaySource::Manual,
                archived: false,
                wrapped_at: None,
                version: AggregateVersion(2),
                updated_at: t,
            },
        ),
        snapshot(
            "costume_category_view",
            &CostumeCategoryView {
                id: category_id,
                season_id: SeasonId(season_id),
                name: "Oberteil".to_string(),
                order_key: LexicalSortKey::from_static("!b"),
                archived: false,
                version: AggregateVersion(1),
                updated_at: t,
            },
        ),
        snapshot(
            "membership_view",
            &MembershipView {
                block_id: BlockId(block_id),
                user_id: user_id.clone(),
                role: Role::CostumeAssistant,
                state: MembershipStateKind::Active,
                joined_at: t,
            },
        ),
    ]
}

fn fixture_path(name: &str) -> PathBuf {
    PathBuf::from(FIXTURES_DIR).join(format!("{name}.json"))
}

/// Regenerate `fixtures/wire/*.json` from the current DTO shapes.
///
/// Deliberate, classification-first act (ADR-021 D3/D5): extend
/// `ADDITIVE_ALLOWLIST` for tolerated additive fields (MINOR) or ship a new
/// `/v{n+1}` for anything else (MAJOR) — never just re-capture silently.
#[test]
#[ignore = "fixture regeneration is a deliberate ADR-021 classification act"]
fn capture_wire_fixtures() {
    std::fs::create_dir_all(FIXTURES_DIR).expect("fixture dir must be creatable");
    for (name, value) in sample_views() {
        let path = fixture_path(name);
        std::fs::write(
            &path,
            serde_json::to_string_pretty(&value).expect("serialize"),
        )
        .expect("fixture must be writable");
        println!("captured {}", path.display());
    }
}

/// Recursively diff `current` against the frozen `fixture` (old), enforcing
/// the ADR-021 D5/D6 rules:
/// - removed key        → hard failure (MAJOR)
/// - changed value      → hard failure (MAJOR, incl. shifted `serde` default)
/// - new key            → hard failure unless allowlisted (MINOR additive)
fn diff_against_fixture(dto: &str, fixture: &Value, current: &Value, path: &str) -> Result<()> {
    match (fixture, current) {
        (Value::Object(old), Value::Object(new)) => {
            for (key, old_val) in old {
                let key_path = format!("{path}.{key}");
                match new.get(key) {
                    None => bail!(
                        "{dto}: field `{key_path}` was REMOVED from the wire contract — \
                         MAJOR (ADR-021 D2/D5), requires a new /v{{n+1}} path version"
                    ),
                    Some(new_val) => diff_against_fixture(dto, old_val, new_val, &key_path)?,
                }
            }
            for (key, new_val) in new {
                if old.contains_key(key) {
                    continue;
                }
                let key_path = format!("{path}.{key}");
                let allowlisted = ADDITIVE_ALLOWLIST
                    .iter()
                    .any(|(d, k)| *d == dto && *k == key_path);
                if !allowlisted {
                    bail!(
                        "{dto}: field `{key_path}` (new value {new_val}) is NEW in the wire \
                         contract — classify it (ADR-021 D3/D5): allowlist it for a \
                         default-identical additive field (MINOR), or ship a new \
                         /v{{n+1}} for anything else (MAJOR)"
                    );
                }
            }
            Ok(())
        }
        _ => {
            if fixture == current {
                Ok(())
            } else {
                bail!(
                    "{dto}: value of `{path}` changed from {fixture} to {current} — MAJOR \
                     (ADR-021 D5, incl. shifted `serde` default)"
                );
            }
        }
    }
}

/// The wire-contract gate: every frozen response fixture must still match the
/// live serialization byte-for-byte (modulo the additive allowlist).
#[test]
fn wire_fixtures_match_live_serialization() {
    let samples = sample_views();
    assert!(!samples.is_empty(), "wire fixture set must not be vacuous");
    for (name, current) in samples {
        let path = fixture_path(name);
        let fixture: Value =
            serde_json::from_str(&std::fs::read_to_string(&path).unwrap_or_else(|e| {
                panic!(
                    "missing wire fixture {}: {e} — run `capture_wire_fixtures`",
                    path.display()
                )
            }))
            .expect("fixture must parse");
        diff_against_fixture(name, &fixture, &current, name)
            .unwrap_or_else(|e| panic!("wire-contract drift for {name}: {e:#}"));
    }
}

/// The fixture set must stay in sync with `sample_views` — a fixture that is
/// no longer produced (route removed) is itself a MAJOR signal.
#[test]
fn no_stale_wire_fixtures() {
    let on_disk: BTreeSet<String> = std::fs::read_dir(FIXTURES_DIR)
        .expect("fixtures dir must exist")
        .filter_map(|e| e.ok())
        .filter_map(|e| {
            e.file_name()
                .into_string()
                .ok()
                .filter(|n| n.ends_with(".json"))
                .map(|n| n.trim_end_matches(".json").to_string())
        })
        .collect();
    let produced: BTreeSet<String> = sample_views()
        .into_iter()
        .map(|(name, _)| name.to_string())
        .collect();
    if let Some(stale) = on_disk.difference(&produced).next() {
        panic!(
            "stale wire fixture {stale}.json: the DTO/route it covered is gone — \
             confirm the removal was a MAJOR /v{{n+1}} change and delete the fixture"
        );
    }
}
