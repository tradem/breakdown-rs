// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024 Breakdown RS Contributors

//! Character aggregate using `kameo_es` event-sourced actor pattern.

use kameo_es::{Apply, Command, Context, Entity, Metadata};
use uuid::Uuid;

use crate::shared::{AggregateVersion, ProjectId};

use super::commands::{CreateCharacter, UpdateContactInfo, UpdateMeasurements};
use super::error::CharacterError;
use super::events::{CharacterEvent, CharacterMeasurements, ContactInfo};

/// State persisted by the Character aggregate.
#[derive(Debug, Clone, Default)]
pub struct CharacterAggregate {
    pub id: Uuid,
    pub project_id: ProjectId,
    pub name: String,
    pub is_extra: bool,
    pub is_main_character: bool,
    pub measurements: CharacterMeasurements,
    pub contact_info: ContactInfo,
    pub version: AggregateVersion,
}

impl Entity for CharacterAggregate {
    type ID = Uuid;
    type Event = CharacterEvent;
    type Metadata = ();

    fn category() -> &'static str {
        "character"
    }
}

impl Apply for CharacterAggregate {
    fn apply(&mut self, event: Self::Event, _metadata: Metadata<()>) {
        match event {
            CharacterEvent::CharacterCreated {
                id,
                project_id,
                name,
                is_extra,
                is_main_character,
                measurements,
                contact_info,
                version,
            } => {
                self.id = id;
                self.project_id = project_id;
                self.name = name;
                self.is_extra = is_extra;
                self.is_main_character = is_main_character;
                self.measurements = measurements;
                self.contact_info = contact_info;
                self.version = version;
            }
            CharacterEvent::MeasurementsUpdated {
                measurements,
                version,
                ..
            } => {
                self.measurements = measurements;
                self.version = version;
            }
            CharacterEvent::ContactInfoUpdated {
                contact_info,
                version,
                ..
            } => {
                self.contact_info = contact_info;
                self.version = version;
            }
        }
    }
}

impl Command<CreateCharacter> for CharacterAggregate {
    type Error = CharacterError;
    fn handle(
        &self,
        cmd: CreateCharacter,
        _ctx: Context<'_, Self>,
    ) -> Result<Vec<Self::Event>, Self::Error> {
        if cmd.name.is_empty() {
            return Err(CharacterError::ValidationError(
                "Name must not be empty".to_string(),
            ));
        }
        Ok(vec![CharacterEvent::CharacterCreated {
            id: cmd.id,
            project_id: cmd.project_id,
            name: cmd.name,
            is_extra: cmd.is_extra,
            is_main_character: cmd.is_main_character,
            measurements: CharacterMeasurements::default(),
            contact_info: ContactInfo::default(),
            version: AggregateVersion::INITIAL,
        }])
    }
}

impl Command<UpdateMeasurements> for CharacterAggregate {
    type Error = CharacterError;
    fn handle(
        &self,
        cmd: UpdateMeasurements,
        _ctx: Context<'_, Self>,
    ) -> Result<Vec<Self::Event>, Self::Error> {
        if cmd.version != self.version {
            return Err(CharacterError::ValidationError(
                "Aggregate version mismatch".to_string(),
            ));
        }
        if cmd.measurements == self.measurements {
            return Err(CharacterError::ValidationError(
                "Measurements unchanged".to_string(),
            ));
        }
        let new_version = self.version.next();
        Ok(vec![CharacterEvent::MeasurementsUpdated {
            id: self.id,
            measurements: cmd.measurements,
            version: new_version,
        }])
    }
}

impl Command<UpdateContactInfo> for CharacterAggregate {
    type Error = CharacterError;
    fn handle(
        &self,
        cmd: UpdateContactInfo,
        _ctx: Context<'_, Self>,
    ) -> Result<Vec<Self::Event>, Self::Error> {
        if cmd.version != self.version {
            return Err(CharacterError::ValidationError(
                "Aggregate version mismatch".to_string(),
            ));
        }
        if cmd.contact_info == self.contact_info {
            return Err(CharacterError::ValidationError(
                "Contact info unchanged".to_string(),
            ));
        }
        let new_version = self.version.next();
        Ok(vec![CharacterEvent::ContactInfoUpdated {
            id: self.id,
            contact_info: cmd.contact_info,
            version: new_version,
        }])
    }
}

// ── Tests ──────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;
    use rust_decimal::Decimal;
    use std::str::FromStr;
    use test_support::make_ctx;

    fn create_character(name: &str) -> CharacterAggregate {
        let project_id = ProjectId::new();
        let cmd = CreateCharacter {
            id: Uuid::now_v7(),
            project_id,
            name: name.to_string(),
            is_extra: false,
            is_main_character: true,
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
        let project_id = ProjectId::new();
        let cmd = CreateCharacter {
            id: Uuid::now_v7(),
            project_id,
            name: "Hans Müller".to_string(),
            is_extra: false,
            is_main_character: true,
        };
        let result = CharacterAggregate::default().handle(cmd, make_ctx());
        assert!(result.is_ok());
        let evt = result.unwrap().into_iter().next().unwrap();
        match evt {
            CharacterEvent::CharacterCreated {
                name,
                is_extra,
                is_main_character,
                version,
                id,
                ..
            } => {
                assert_eq!(name, "Hans Müller");
                assert!(!is_extra);
                assert!(is_main_character);
                assert_eq!(version, AggregateVersion::INITIAL);
                assert_ne!(id, Uuid::nil());
            }
            _ => panic!("Expected CharacterCreated"),
        }
    }

    #[test]
    fn test_create_character_empty_name() {
        let project_id = ProjectId::new();
        let cmd = CreateCharacter {
            id: Uuid::now_v7(),
            project_id,
            name: String::new(),
            is_extra: false,
            is_main_character: false,
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
        let mut agg = create_character("Test");
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
        let agg = create_character("Test");
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
        let agg = create_character("Test");
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
        let mut agg = create_character("Test");
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
        let agg = create_character("Test");
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
        let agg = create_character("Test");
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
        let project_id = ProjectId::new();
        agg.apply(
            CharacterEvent::CharacterCreated {
                id,
                project_id,
                name: "Liese".into(),
                is_extra: false,
                is_main_character: true,
                measurements: CharacterMeasurements::default(),
                contact_info: ContactInfo::default(),
                version: AggregateVersion::INITIAL,
            },
            Metadata::default(),
        );
        assert_eq!(agg.name, "Liese", "apply() should set the character name");
        assert_eq!(agg.id, id, "apply() should set the character id");
        assert!(!agg.is_extra);
        assert!(agg.is_main_character);
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
        let project_id = ProjectId::new();
        let phone = "+49 170 111".to_string();
        agg.apply(
            CharacterEvent::CharacterCreated {
                id,
                project_id,
                name: "Test".into(),
                is_extra: false,
                is_main_character: false,
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
} // mod tests
