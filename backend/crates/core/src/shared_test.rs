// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors

use super::*;

fn assert_between(a: &str, mid: &str, b: &str) {
    let ka = LexicalSortKey::new(a).unwrap();
    let kb = LexicalSortKey::new(b).unwrap();
    let kmid = LexicalSortKey::new(mid).unwrap();
    assert!(
        ka < kmid && kmid < kb,
        "expected {a:?} < {mid:?} < {b:?} (got {ka:?} < {kmid:?} < {kb:?})"
    );
}

fn key(s: &str) -> LexicalSortKey {
    LexicalSortKey::new(s).unwrap()
}

#[test]
fn midpoint_returns_exact_expected_keys() {
    // Adjacent bytes (no shared prefix): append the alphabet minimum.
    assert_eq!(LexicalSortKey::midpoint(&key("a"), &key("b")), Ok(key("a!")));
    // Gap of >= 2 (no shared prefix): emit lo + 1.
    assert_eq!(LexicalSortKey::midpoint(&key("a"), &key("z")), Ok(key("b")));
    // Adjacent bytes with a shared prefix: append the alphabet minimum to `a`.
    assert_eq!(
        LexicalSortKey::midpoint(&key("ab"), &key("ac")),
        Ok(key("ab!"))
    );
    // Gap of >= 2 with a shared prefix: emit prefix + (lo + 1).
    assert_eq!(
        LexicalSortKey::midpoint(&key("ab"), &key("ad")),
        Ok(key("ac"))
    );
    // `a` is a strict prefix of `b`: extend `a` with the alphabet minimum.
    assert_eq!(
        LexicalSortKey::midpoint(&key("a"), &key("aa")),
        Ok(key("a!"))
    );
    assert_eq!(
        LexicalSortKey::midpoint(&key("abc"), &key("abd")),
        Ok(key("abc!"))
    );
}

#[test]
fn lexical_sort_key_display_roundtrip() {
    // Display must surface the underlying key verbatim (kills the `Display`
    // mutant that returns `Ok(Default::default())` → empty string).
    let k = LexicalSortKey::from_static("a!b");
    assert_eq!(format!("{k}"), "a!b");
    assert_eq!(format!("{}", LexicalSortKey::from_static("z")), "z");
}

#[test]
fn midpoint_rejects_unordered_bounds() {
    let a = LexicalSortKey::new("b").unwrap();
    let b = LexicalSortKey::new("a").unwrap();
    assert_eq!(LexicalSortKey::midpoint(&a, &b), Err(LexicalSortKeyError::NoRoom));

    // Equal bounds have no room between them.
    let same = LexicalSortKey::new("x").unwrap();
    assert_eq!(LexicalSortKey::midpoint(&same, &same), Err(LexicalSortKeyError::NoRoom));
}

#[test]
fn lexical_sort_key_rejects_invalid_inputs() {
    // Empty string.
    assert_eq!(LexicalSortKey::new(""), Err(LexicalSortKeyError::Empty));

    // Whitespace is outside the alphabet.
    assert_eq!(
        LexicalSortKey::new("a b"),
        Err(LexicalSortKeyError::InvalidChar)
    );

    // Non-ASCII character.
    assert_eq!(
        LexicalSortKey::new("café"),
        Err(LexicalSortKeyError::InvalidChar)
    );

    // Too long.
    let too_long = "a".repeat(65);
    assert_eq!(
        LexicalSortKey::new(too_long),
        Err(LexicalSortKeyError::TooLong(64))
    );
}

#[test]
fn lexical_sort_key_compares_lexicographically() {
    let a = LexicalSortKey::new("a").unwrap();
    let b = LexicalSortKey::new("b").unwrap();
    let aa = LexicalSortKey::new("aa").unwrap();
    assert!(a < aa);
    assert!(aa < b);
    assert!(a < b);
}

#[test]
fn shooting_day_id_display_and_parse_roundtrip() {
    let id = ShootingDayId::new();
    let s = id.to_string();
    let back: ShootingDayId = s.parse().expect("ShootingDayId must parse its Display output");
    assert_eq!(id, back);
    assert_eq!(back.0, id.0);
    // Display is the bare UUID string.
    assert_eq!(s, id.0.to_string());
}

#[test]
fn shooting_day_id_rejects_non_uuid() {
    assert!("not-a-uuid".parse::<ShootingDayId>().is_err());
}

#[test]
fn midpoint_rejects_empty_bound() {
    let empty = LexicalSortKey(String::new());
    let b = LexicalSortKey::new("b").unwrap();
    // Either bound empty must be rejected (guards the `||` in `midpoint`).
    assert_eq!(
        LexicalSortKey::midpoint(&empty, &b),
        Err(LexicalSortKeyError::Empty)
    );
    assert_eq!(
        LexicalSortKey::midpoint(&b, &empty),
        Err(LexicalSortKeyError::Empty)
    );
}


#[test]
fn shooting_day_id_from_uuid_preserves_value() {
    let raw = Uuid::now_v7();
    assert_eq!(ShootingDayId::from_uuid(raw).0, raw);
}

#[test]
fn shooting_day_id_is_uuidv7() {
    let id = ShootingDayId::new();
    assert_ne!(id.0, Uuid::nil());
}

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
