// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3 (neuralwatt)
// Co-authored-by: glm-5.3-flash (opencode-go)

//! Synthetic reservation "entity" for ADR-036 (issue #586).
//!
//! Reservation streams are **bookkeeping, not domain events**: they live in
//! SierraDB under the `reservation` category so the standard `kameo_es`
//! projector pipeline (checksums, #37 DLQ, runbook health) can observe them,
//! but they are never replayed into a domain aggregate. This module provides
//! the minimal pseudo-`Entity` the projector pipeline needs to deserialize
//! reservation payloads, plus the key construction shared with the store and
//! the reaper.

use serde::{Deserialize, Serialize};
use uuid::Uuid;

use breakdown_core::shared::EventMetadata;

/// SierraDB category of all reservation streams (`reservation-<rest>`).
pub const RESERVATION_CATEGORY: &str = "reservation";

/// Prefix of every reservation stream id; the remainder is the opaque key.
pub const RESERVATION_STREAM_PREFIX: &str = "reservation-";

/// ADR-036 claim lifecycle event names.
pub const EVENT_NAME_RESERVED: &str = "ReservationReserved";
pub const EVENT_NAME_RELEASED: &str = "ReservationReleased";
pub const EVENT_NAME_CONSUMED: &str = "ReservationConsumed";

/// ADR-036 claim lifecycle payloads (CBOR-encoded on the wire, mirroring the
/// `kameo_es` envelope convention).
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum ReservationEvent {
    /// A command claimed the key for `aggregate_id`.
    Reserved { aggregate_id: Uuid },
    /// The holder gave the key back (create-failure or reaper orphan release).
    Released { aggregate_id: Uuid },
    /// The reaper observed the claim has become permanently true (the claimed
    /// aggregate stream exists). Keys owned by a realized aggregate can never
    /// be released in today's domain (no delete commands; archived seasons
    /// keep their number reserved, issue #533).
    Consumed { aggregate_id: Uuid },
}

/// Required by the `kameo_es` projector pipeline's event envelope; the
/// distinguishable type name for the whole lifecycle family.
impl kameo_es::EventType for ReservationEvent {
    fn event_type(&self) -> &'static str {
        match self {
            Self::Reserved { .. } => EVENT_NAME_RESERVED,
            Self::Released { .. } => EVENT_NAME_RELEASED,
            Self::Consumed { .. } => EVENT_NAME_CONSUMED,
        }
    }
}

impl ReservationEvent {
    /// Every lifecycle event carries the involved aggregate id — used by the
    /// reaper to identify the claim holder and by the projector to mirror it.
    pub fn aggregate_id(&self) -> Uuid {
        match self {
            Self::Reserved { aggregate_id }
            | Self::Released { aggregate_id }
            | Self::Consumed { aggregate_id } => *aggregate_id,
        }
    }
}

/// Discriminates the four migrated invariants in the projector table and in
/// the reaper's aggregate-stream probe (ADR-036 §3).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ReservationKind {
    EpisodeNumber,
    SeasonNumber,
    BlockNumber,
    SceneShootPair,
}

impl ReservationKind {
    /// Derives the invariant from a reservation key's prefix (the key shapes
    /// are fixed in this module's key builders).
    pub fn from_key(key: &str) -> Option<Self> {
        if key.starts_with("epnum-") {
            Some(Self::EpisodeNumber)
        } else if key.starts_with("seasnum-") {
            Some(Self::SeasonNumber)
        } else if key.starts_with("blocknum-") {
            Some(Self::BlockNumber)
        } else if key.starts_with("sspair-") {
            Some(Self::SceneShootPair)
        } else {
            None
        }
    }

    /// Aggregate event-stream category whose mere existence realizes the
    /// claim permanently (the reaper's `esver` probe target).
    pub fn aggregate_category(self) -> &'static str {
        match self {
            Self::EpisodeNumber => "episode",
            Self::SeasonNumber => "season",
            Self::BlockNumber => "block",
            Self::SceneShootPair => "scene_shoot",
        }
    }

    /// Canonical label used as the projector-table `kind` value and in
    /// tracing/log output.
    pub fn as_str(self) -> &'static str {
        match self {
            Self::EpisodeNumber => "episode_number",
            Self::SeasonNumber => "season_number",
            Self::BlockNumber => "block_number",
            Self::SceneShootPair => "scene_shoot_pair",
        }
    }
}

/// Builds the opaque reservation key (the part after the `reservation-`
/// stream prefix). Shapes follow ADR-035 B4: the tenant-scoped container id
/// leads the key.
///
/// SierraDB stream ids are capped at 64 characters (server INVALIDARG), so:
/// - the tenant id is emitted as compact UUID hex (32 chars, not the dashed
///   36-char form), and
/// - the `(scene_id, shooting_day_id)` pair collapses into a truncated
///   SHA-256 (12 bytes = 24 hex chars) — a birthday collision would need
///   ~2^48 concurrently-planned pairs to matter, far beyond anything this
///   domain models, and a collision errs conservative (one extra 409).
pub fn episode_number_key(series_id: Uuid, number: i32) -> String {
    format!("epnum-{}-{number}", uuid_simple(series_id))
}

pub fn season_number_key(series_id: Uuid, number: i32) -> String {
    format!("seasnum-{}-{number}", uuid_simple(series_id))
}

pub fn block_number_key(series_id: Uuid, number: i32) -> String {
    format!("blocknum-{}-{number}", uuid_simple(series_id))
}

pub fn scene_shoot_pair_key(scene_id: Uuid, shooting_day_id: Uuid) -> String {
    use sha2::{Digest, Sha256};
    let mut hasher = Sha256::new();
    hasher.update(scene_id.as_bytes());
    hasher.update(shooting_day_id.as_bytes());
    let digest = hasher.finalize();
    let hex: String = digest[..12].iter().map(|b| format!("{b:02x}")).collect();
    format!("sspair-{hex}")
}

/// Compact (dashless) hex form of a UUID — 32 characters.
fn uuid_simple(id: Uuid) -> impl std::fmt::Display {
    id.simple()
}

/// Full SierraDB stream id for a reservation key.
pub fn reservation_stream_id(key: &str) -> String {
    format!("{RESERVATION_STREAM_PREFIX}{key}")
}

/// Pseudo-`Entity` so the `kameo_es` event-handler machinery routes
/// `reservation`-category events to the reservation projector. There is no
/// aggregate behind it: state lives in the projector table (key = stream key
/// text), which is also why `ID = String` parses from the cardinal id
/// (everything after the category/dash separator).
#[derive(Debug, Clone, Default)]
pub struct ReservationEntity;

impl kameo_es::Entity for ReservationEntity {
    type ID = String;
    type Event = ReservationEvent;
    type Metadata = EventMetadata;

    fn category() -> &'static str {
        RESERVATION_CATEGORY
    }
}

#[cfg(test)]
mod tests {
    use uuid::Uuid;

    use super::*;

    /// SierraDB caps stream ids at 64 characters — every key builder must
    /// produce ids that fit (with the `reservation-` prefix).
    #[test]
    fn key_builders_respect_the_sierradb_stream_id_cap() {
        let big = Uuid::now_v7();
        let max = i32::MAX;
        for (key, kind) in [
            (episode_number_key(big, max), ReservationKind::EpisodeNumber),
            (season_number_key(big, max), ReservationKind::SeasonNumber),
            (block_number_key(big, max), ReservationKind::BlockNumber),
        ] {
            let stream_id = reservation_stream_id(&key);
            assert!(
                stream_id.len() <= 64,
                "stream id '{stream_id}' exceeds the 64-char cap"
            );
            assert_eq!(ReservationKind::from_key(&key), Some(kind));
        }
        let pair = scene_shoot_pair_key(big, Uuid::now_v7());
        let stream_id = reservation_stream_id(&pair);
        assert!(
            stream_id.len() <= 64,
            "stream id '{stream_id}' exceeds the cap"
        );
        assert_eq!(
            ReservationKind::from_key(&pair),
            Some(ReservationKind::SceneShootPair)
        );
        // Hash form: 24 hex chars after the prefix.
        let hex = pair.strip_prefix("sspair-").unwrap();
        assert_eq!(hex.len(), 24);
        assert!(
            hex.chars()
                .all(|c| c.is_ascii_digit() || ('a'..='f').contains(&c))
        );
    }

    /// Deterministic key derivation: same pair → same key (the reaper probe
    /// and re-reserve CAS both rely on this convergence).
    #[test]
    fn scene_shoot_pair_key_is_deterministic() {
        let (a, b) = (Uuid::now_v7(), Uuid::now_v7());
        assert_eq!(scene_shoot_pair_key(a, b), scene_shoot_pair_key(a, b));
        assert_ne!(scene_shoot_pair_key(a, b), scene_shoot_pair_key(b, a));
    }

    /// The pseudo-entity routes the `reservation` category.
    #[test]
    fn reservation_entity_category() {
        assert_eq!(
            <ReservationEntity as kameo_es::Entity>::category(),
            "reservation"
        );
    }
}
