// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors

use super::*;
use rust_decimal::Decimal;
use std::str::FromStr;
use test_support::make_ctx;

fn create_character(name: &str, category: CharacterCategory) -> CharacterAggregate {
    let season_id = SeasonId::new();
    let cmd = CreateCharacter {
        id: Uuid::now_v7(),
        season_id,
        name: name.to_string(),
        category,
    };
    let events = CharacterAggregate::default()
        .handle(cmd, make_ctx())
        .unwrap();
    let mut agg = CharacterAggregate::default();
    test_support::replay_events(&mut agg, events);
    agg
}

#[test]
fn test_create_character_success() {
    let season_id = SeasonId::new();
    let cmd = CreateCharacter {
        id: Uuid::now_v7(),
        season_id,
        name: "Hans Müller".to_string(),
        category: CharacterCategory::MainCast,
    };
    let result = CharacterAggregate::default().handle(cmd, make_ctx());
    assert!(result.is_ok());
    let evt = result.unwrap().into_iter().next().unwrap();
    match evt {
        CharacterEvent::CharacterCreated {
            name,
            category,
            version,
            id,
            ..
        } => {
            assert_eq!(name, "Hans Müller");
            assert_eq!(category, CharacterCategory::MainCast);
            assert_eq!(version, AggregateVersion::INITIAL);
            assert_ne!(id, Uuid::nil());
        }
        _ => panic!("Expected CharacterCreated"),
    }
}

#[test]
fn test_create_character_empty_name() {
    let season_id = SeasonId::new();
    let cmd = CreateCharacter {
        id: Uuid::now_v7(),
        season_id,
        name: String::new(),
        category: CharacterCategory::MainCast,
    };
    let result = CharacterAggregate::default().handle(cmd, make_ctx());
    assert!(result.is_err());
    assert!(matches!(
        result.unwrap_err(),
        CharacterError::ValidationError(_)
    ));
}

#[test]
fn test_update_measurements_success() {
    let mut agg = create_character("Test", CharacterCategory::MainCast);
    let measurements = CharacterMeasurements {
        shoe_size: Some(Decimal::from_str("42").unwrap()),
        height: Some(Decimal::from_str("1.85").unwrap()),
        ..Default::default()
    };
    let cmd = UpdateMeasurements {
        id: agg.id,
        measurements: measurements.clone(),
        version: agg.version,
    };
    let events = agg.handle(cmd, make_ctx()).unwrap();
    assert_eq!(events.len(), 1);
    if let CharacterEvent::MeasurementsUpdated { version, .. } = &events[0] {
        assert_eq!(*version, AggregateVersion(2));
    } else {
        panic!("Expected MeasurementsUpdated");
    }
    test_support::replay_events(&mut agg, events);
    assert_eq!(
        agg.measurements.shoe_size,
        Some(Decimal::from_str("42").unwrap())
    );
    assert_eq!(agg.version, AggregateVersion(2));
}

#[test]
fn test_update_measurements_idempotency() {
    let agg = create_character("Test", CharacterCategory::MainCast);
    let cmd = UpdateMeasurements {
        id: agg.id,
        measurements: agg.measurements.clone(),
        version: agg.version,
    };
    let result = agg.handle(cmd, make_ctx());
    assert!(result.is_err());
    assert!(matches!(
        result.unwrap_err(),
        CharacterError::ValidationError(ref m) if m.contains("unchanged")
    ));
}

#[test]
fn test_update_measurements_wrong_version() {
    let agg = create_character("Test", CharacterCategory::MainCast);
    let cmd = UpdateMeasurements {
        id: agg.id,
        measurements: CharacterMeasurements {
            shoe_size: Some(Decimal::from_str("42").unwrap()),
            ..Default::default()
        },
        version: AggregateVersion(99),
    };
    let result = agg.handle(cmd, make_ctx());
    assert!(result.is_err());
    assert!(matches!(
        result.unwrap_err(),
        CharacterError::ValidationError(ref m) if m.contains("version mismatch")
    ));
}

#[test]
fn test_update_contact_info_success() {
    let mut agg = create_character("Test", CharacterCategory::Guest);
    let contact = ContactInfo {
        phone: Some("+49 170 1234567".to_string()),
        email: Some("hans@example.de".to_string()),
    };
    let cmd = UpdateContactInfo {
        id: agg.id,
        contact_info: contact.clone(),
        version: agg.version,
    };
    let event = agg.handle(cmd, make_ctx());
    test_support::replay_events(&mut agg, event.unwrap());
    assert_eq!(agg.contact_info.phone, contact.phone);
    assert_eq!(agg.contact_info.email, contact.email);
}

#[test]
fn test_update_contact_info_idempotency() {
    let agg = create_character("Test", CharacterCategory::Guest);
    let cmd = UpdateContactInfo {
        id: agg.id,
        contact_info: agg.contact_info.clone(),
        version: agg.version,
    };
    let result = agg.handle(cmd, make_ctx());
    assert!(result.is_err());
    assert!(matches!(
        result.unwrap_err(),
        CharacterError::ValidationError(ref m) if m.contains("unchanged")
    ));
}

#[test]
fn test_update_contact_info_wrong_version() {
    let agg = create_character("Test", CharacterCategory::Guest);
    let cmd = UpdateContactInfo {
        id: agg.id,
        contact_info: ContactInfo {
            phone: Some("test".to_string()),
            email: None,
        },
        version: AggregateVersion(99),
    };
    let result = agg.handle(cmd, make_ctx());
    assert!(result.is_err());
    assert!(matches!(
        result.unwrap_err(),
        CharacterError::ValidationError(ref m) if m.contains("version mismatch")
    ));
}

/// Verify that apply() actually mutates aggregate state.
///
/// Catches mutants that replace the `apply` body with `()` — if apply is a
/// no-op the assertion below fails because the character stays at its
/// default (empty name).
#[test]
fn test_apply_updates_state() {
    use kameo_es::Metadata;
    let mut agg = CharacterAggregate::default();
    let id = Uuid::now_v7();
    let season_id = SeasonId::new();
    agg.apply(
        CharacterEvent::CharacterCreated {
            id,
            season_id,
            name: "Liese".into(),
            category: CharacterCategory::MainCast,
            measurements: CharacterMeasurements::default(),
            contact_info: ContactInfo::default(),
            version: AggregateVersion::INITIAL,
        },
        Metadata::default(),
    );
    assert_eq!(agg.name, "Liese", "apply() should set the character name");
    assert_eq!(agg.id, id, "apply() should set the character id");
    assert_eq!(agg.category, CharacterCategory::MainCast);
    assert_eq!(agg.version, AggregateVersion::INITIAL);
}

/// Verify that the idempotency check in UpdateContactInfo uses `!=` (not
/// `==`), so passing identical contact info correctly returns an error.
#[test]
fn test_update_contact_info_idempotency_uses_not_equal() {
    use kameo_es::Metadata;
    let mut agg = CharacterAggregate::default();
    // Start with contact info set.
    let id = Uuid::now_v7();
    let season_id = SeasonId::new();
    let phone = "+49 170 111".to_string();
    agg.apply(
        CharacterEvent::CharacterCreated {
            id,
            season_id,
            name: "Test".into(),
            category: CharacterCategory::MainCast,
            measurements: CharacterMeasurements::default(),
            contact_info: ContactInfo::default(),
            version: AggregateVersion::INITIAL,
        },
        Metadata::default(),
    );
    // Apply a ContactInfoUpdated to set the contact info.
    agg.apply(
        CharacterEvent::ContactInfoUpdated {
            id,
            contact_info: ContactInfo {
                phone: Some(phone.clone()),
                email: None,
            },
            version: AggregateVersion(2),
        },
        Metadata::default(),
    );
    // Now sending UpdateContactInfo with the SAME info should fail
    // (idempotency check: `cmd.contact_info != self.contact_info`).
    let result = agg.handle(
        UpdateContactInfo {
            id,
            contact_info: ContactInfo {
                phone: Some(phone.clone()),
                email: None,
            },
            version: AggregateVersion(2),
        },
        make_ctx(),
    );
    assert!(
        result.is_err(),
        "identical contact info should be rejected (idempotency check)"
    );
}
