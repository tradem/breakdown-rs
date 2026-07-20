// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors

use super::*;

#[test]
fn initial_is_one() {
    assert_eq!(AggregateVersion::INITIAL.0, 1);
}

#[test]
fn next_increments_by_one() {
    let v0 = AggregateVersion::INITIAL;
    let v1 = v0.next();
    assert_eq!(v1.0, 2);

    let v2 = v1.next();
    assert_eq!(v2.0, 3);
}

#[test]
fn default_is_initial() {
    assert_eq!(AggregateVersion::default(), AggregateVersion::INITIAL);
}

#[test]
fn series_id_is_uuidv7() {
    let id = SeriesId::new();
    assert_ne!(id.0, Uuid::nil());
}

#[test]
fn season_id_is_uuidv7() {
    let id = SeasonId::new();
    assert_ne!(id.0, Uuid::nil());
}

#[test]
fn block_id_is_uuidv7() {
    let id = BlockId::new();
    assert_ne!(id.0, Uuid::nil());
}

#[test]
fn episode_id_is_uuidv7() {
    let id = EpisodeId::new();
    assert_ne!(id.0, Uuid::nil());
}

#[test]
fn series_id_from_uuid_preserves_value() {
    let raw = Uuid::now_v7();
    assert_eq!(SeriesId::from_uuid(raw).0, raw);
}

#[test]
fn season_id_from_uuid_preserves_value() {
    let raw = Uuid::now_v7();
    assert_eq!(SeasonId::from_uuid(raw).0, raw);
}

#[test]
fn block_id_from_uuid_preserves_value() {
    let raw = Uuid::now_v7();
    assert_eq!(BlockId::from_uuid(raw).0, raw);
}

#[test]
fn user_id_serializes_transparent_like_sub() {
    let id = UserId::from_sub("user_8xK2".to_string());
    let json = serde_json::to_string(&id).unwrap();
    assert_eq!(json, "\"user_8xK2\"");
    // Round-trips back to the same subject (parity with the IdP `sub`).
    let back: UserId = serde_json::from_str(&json).unwrap();
    assert_eq!(back, id);
    assert_eq!(back.as_str(), "user_8xK2");
}

#[test]
fn user_id_preserves_opaque_sub_through_clone() {
    let id = UserId::from_sub("auth0|abc123".to_string());
    let cloned = id.clone();
    assert_eq!(id, cloned);
    assert_eq!(format!("{id}"), "auth0|abc123");
}
