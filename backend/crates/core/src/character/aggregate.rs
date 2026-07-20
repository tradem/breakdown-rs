// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors

//! Character aggregate using `kameo_es` event-sourced actor pattern.

use kameo_es::{Apply, Command, Context, Entity, Metadata};
use uuid::Uuid;

use crate::shared::{AggregateVersion, SeasonId};

use super::category::CharacterCategory;
use super::commands::{CreateCharacter, UpdateContactInfo, UpdateMeasurements};
use super::error::CharacterError;
use super::events::{CharacterEvent, CharacterMeasurements, ContactInfo};

/// State persisted by the Character aggregate.
///
/// A Character is scoped to exactly one `SeasonId`. Its role type is captured
/// by a single exhaustive `CharacterCategory` enum (no boolean flags).
#[derive(Debug, Clone, Default)]
pub struct CharacterAggregate {
    pub id: Uuid,
    pub season_id: SeasonId,
    pub name: String,
    pub category: CharacterCategory,
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

// ADR-002 (Event Sourcing / CQRS): Apply replays past events to rebuild
// aggregate state. Every command handler emits events that are applied here.
impl Apply for CharacterAggregate {
    fn apply(&mut self, event: Self::Event, _metadata: Metadata<()>) {
        match event {
            CharacterEvent::CharacterCreated {
                id,
                season_id,
                name,
                category,
                measurements,
                contact_info,
                version,
            } => {
                self.id = id;
                self.season_id = season_id;
                self.name = name;
                self.category = category;
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

// ADR-002 (Event Sourcing / CQRS): Commands validate invariants and emit
// events. The aggregate state is never mutated directly — only via Apply.
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
            season_id: cmd.season_id,
            name: cmd.name,
            category: cmd.category,
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
#[path = "aggregate_test.rs"]
mod tests;
