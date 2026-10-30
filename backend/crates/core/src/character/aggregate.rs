// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash-flex (neuralwatt)
// Co-authored-by: deepseek-v4-flash (neuralwatt)
// Co-authored-by: mimo-v2.5 (opencode-go)

//! Character aggregate using `kameo_es` event-sourced actor pattern.

use kameo_es::{Apply, Command, Context, Entity, Metadata};
use uuid::Uuid;

use crate::shared::{AggregateVersion, EventMetadata, SeasonId};

use super::category::CharacterCategory;
use super::commands::{
    CreateCharacter, DeleteCharacter, UpdateCharacterCategory, UpdateContactInfo,
    UpdateMeasurements,
};
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
    /// Set by the terminal `CharacterDeleted` event: a deleted
    /// aggregate rejects every further command (issue #770 — a delete
    /// must not leave a stream that still accepts mutations).
    pub deleted: bool,
    pub version: AggregateVersion,
}

impl Entity for CharacterAggregate {
    type ID = Uuid;
    type Event = CharacterEvent;
    type Metadata = EventMetadata;

    fn category() -> &'static str {
        "character"
    }
}

// ADR-002 (Event Sourcing / CQRS): Apply replays past events to rebuild
// aggregate state. Every command handler emits events that are applied here.
impl Apply for CharacterAggregate {
    fn apply(&mut self, event: Self::Event, _metadata: Metadata<EventMetadata>) {
        match event {
            // Issue #770 (dev data reset): the delete carries no further state
            // change — the projector removes the projection row and the stream
            // keeps its history for the audit trail.
            CharacterEvent::CharacterDeleted { version, .. } => {
                self.deleted = true;
                self.version = version;
            }
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
            CharacterEvent::CategoryChanged {
                category, version, ..
            } => {
                self.category = category;
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
        if self.deleted {
            return Err(CharacterError::Deleted { id: self.id });
        }
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
        if self.deleted {
            return Err(CharacterError::Deleted { id: self.id });
        }
        if cmd.version != self.version {
            return Err(CharacterError::VersionMismatch {
                expected: cmd.version,
                actual: self.version,
            });
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
        if self.deleted {
            return Err(CharacterError::Deleted { id: self.id });
        }
        if cmd.version != self.version {
            return Err(CharacterError::VersionMismatch {
                expected: cmd.version,
                actual: self.version,
            });
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

impl Command<UpdateCharacterCategory> for CharacterAggregate {
    type Error = CharacterError;
    fn handle(
        &self,
        cmd: UpdateCharacterCategory,
        _ctx: Context<'_, Self>,
    ) -> Result<Vec<Self::Event>, Self::Error> {
        if self.deleted {
            return Err(CharacterError::Deleted { id: self.id });
        }
        if cmd.version != self.version {
            return Err(CharacterError::VersionMismatch {
                expected: cmd.version,
                actual: self.version,
            });
        }
        if cmd.category == self.category {
            // State-based idempotent no-op (same pattern as the costume
            // repertoire add/remove): a repeat write with the current
            // category changes nothing and emits no event. kameo_es maps
            // the empty event list to `ExecuteResult::Idempotent`, which
            // the command adapter answers with the CURRENT version — a
            // repeat caller gets 200 + the version it already knew
            // (CodeRabbit #693), not a 422 refusal.
            return Ok(vec![]);
        }
        let new_version = self.version.next();
        Ok(vec![CharacterEvent::CategoryChanged {
            id: self.id,
            category: cmd.category,
            version: new_version,
        }])
    }
}

// Issue #770 (dev data reset): the delete path for a Character. See
// `DeleteCharacter` for why it has no HTTP route and no port method.
impl Command<DeleteCharacter> for CharacterAggregate {
    type Error = CharacterError;
    fn handle(
        &self,
        cmd: DeleteCharacter,
        _ctx: Context<'_, Self>,
    ) -> Result<Vec<Self::Event>, Self::Error> {
        // Idempotent: deleting an already-deleted aggregate is a no-op.
        if self.deleted {
            return Ok(vec![]);
        }
        // An absent aggregate replays to a default state; deleting it must not
        // fabricate a stream. A repeat delete on an existing aggregate is
        // idempotent at the projection (the DELETE matches nothing twice).
        if self.id.is_nil() {
            return Err(CharacterError::NotFound { id: cmd.id });
        }
        Ok(vec![CharacterEvent::CharacterDeleted {
            id: self.id,
            version: self.version.next(),
        }])
    }
}
