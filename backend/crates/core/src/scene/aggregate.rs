// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024 Breakdown RS Contributors

//! Scene aggregate using `kameo_es` event-sourced actor pattern.

use kameo_es::{Apply, Command, Context, Entity, Metadata};
use uuid::Uuid;

use crate::shared::{AggregateVersion, EpisodeId, ShootingDayId};

use super::commands::{
    AssignCharacter, CreateScene, RemoveCharacter, ScheduleSceneOnShootingDay,
    UnscheduleSceneFromShootingDay, UpdateSceneDetails,
};
use super::error::SceneError;
use super::events::SceneEvent;

use crate::scene::events::SceneDetails;

/// State persisted by the Scene aggregate.
///
/// A Scene references exactly one `EpisodeId` (the work-unit scope). It does
/// NOT carry any production-level scope (Series/Season/Block) directly.
#[derive(Debug, Clone, Default)]
pub struct SceneAggregate {
    pub id: Uuid,
    pub episode_id: EpisodeId,
    pub details: SceneDetails,
    pub assigned_characters: Vec<Uuid>,
    /// Shooting days this scene is linked to (the scene owns the collection).
    pub shooting_day_ids: Vec<ShootingDayId>,
    pub version: AggregateVersion,
}

impl Entity for SceneAggregate {
    type ID = Uuid;
    type Event = SceneEvent;
    type Metadata = ();

    fn category() -> &'static str {
        "scene"
    }
}

// ADR-002 (Event Sourcing / CQRS): Apply replays past events to rebuild
// aggregate state. Every command handler emits events that are applied here.
impl Apply for SceneAggregate {
    fn apply(&mut self, event: Self::Event, _metadata: Metadata<()>) {
        match event {
            SceneEvent::SceneCreated {
                id,
                episode_id,
                details,
                assigned_characters,
                version,
            } => {
                self.id = id;
                self.episode_id = episode_id;
                self.details = details;
                self.assigned_characters = assigned_characters;
                // Legacy `SceneCreated` events carry no shooting-day links; the
                // collection is always initialised empty and grown via commands.
                self.shooting_day_ids = Vec::new();
                self.version = version;
            }
            SceneEvent::SceneDetailsUpdated {
                details, version, ..
            } => {
                self.details = details;
                self.version = version;
            }
            SceneEvent::CharacterAssigned {
                character_id,
                version,
                ..
            } => {
                if !self.assigned_characters.contains(&character_id) {
                    self.assigned_characters.push(character_id);
                }
                self.version = version;
            }
            SceneEvent::CharacterRemoved {
                character_id,
                version,
                ..
            } => {
                self.assigned_characters.retain(|&id| id != character_id);
                self.version = version;
            }
            SceneEvent::ShootingDayScheduled {
                shooting_day_id,
                version,
                ..
            } => {
                if !self.shooting_day_ids.contains(&shooting_day_id) {
                    self.shooting_day_ids.push(shooting_day_id);
                }
                self.version = version;
            }
            SceneEvent::ShootingDayUnscheduled {
                shooting_day_id,
                version,
                ..
            } => {
                self.shooting_day_ids.retain(|&id| id != shooting_day_id);
                self.version = version;
            }
        }
    }
}

// ADR-002 (Event Sourcing / CQRS): Commands validate invariants and emit
// events. The aggregate state is never mutated directly — only via Apply.
impl Command<CreateScene> for SceneAggregate {
    type Error = SceneError;
    fn handle(
        &self,
        cmd: CreateScene,
        _ctx: Context<'_, Self>,
    ) -> Result<Vec<Self::Event>, Self::Error> {
        Ok(vec![SceneEvent::SceneCreated {
            id: cmd.id,
            episode_id: cmd.episode_id,
            details: cmd.details,
            assigned_characters: Vec::new(),
            version: AggregateVersion::INITIAL,
        }])
    }
}

impl Command<UpdateSceneDetails> for SceneAggregate {
    type Error = SceneError;
    fn handle(
        &self,
        cmd: UpdateSceneDetails,
        _ctx: Context<'_, Self>,
    ) -> Result<Vec<Self::Event>, Self::Error> {
        if cmd.version != self.version {
            return Err(SceneError::ValidationError(
                "Aggregate version mismatch".into(),
            ));
        }
        if cmd.details == self.details {
            return Err(SceneError::ValidationError(
                "Scene details unchanged".into(),
            ));
        }
        let new_version = self.version.next();
        Ok(vec![SceneEvent::SceneDetailsUpdated {
            id: self.id,
            details: cmd.details,
            version: new_version,
        }])
    }
}

impl Command<AssignCharacter> for SceneAggregate {
    type Error = SceneError;
    fn handle(
        &self,
        cmd: AssignCharacter,
        _ctx: Context<'_, Self>,
    ) -> Result<Vec<Self::Event>, Self::Error> {
        if cmd.version != self.version {
            return Err(SceneError::ValidationError(
                "Aggregate version mismatch".into(),
            ));
        }
        if self.assigned_characters.contains(&cmd.character_id) {
            return Err(SceneError::CharacterAlreadyAssigned);
        }
        let new_version = self.version.next();
        Ok(vec![SceneEvent::CharacterAssigned {
            id: self.id,
            character_id: cmd.character_id,
            version: new_version,
        }])
    }
}

impl Command<RemoveCharacter> for SceneAggregate {
    type Error = SceneError;
    fn handle(
        &self,
        cmd: RemoveCharacter,
        _ctx: Context<'_, Self>,
    ) -> Result<Vec<Self::Event>, Self::Error> {
        if cmd.version != self.version {
            return Err(SceneError::ValidationError(
                "Aggregate version mismatch".into(),
            ));
        }
        if !self.assigned_characters.contains(&cmd.character_id) {
            return Err(SceneError::ValidationError(
                "Character is not assigned to this scene".into(),
            ));
        }
        let new_version = self.version.next();
        Ok(vec![SceneEvent::CharacterRemoved {
            id: self.id,
            character_id: cmd.character_id,
            version: new_version,
        }])
    }
}

impl Command<ScheduleSceneOnShootingDay> for SceneAggregate {
    type Error = SceneError;
    fn handle(
        &self,
        cmd: ScheduleSceneOnShootingDay,
        _ctx: Context<'_, Self>,
    ) -> Result<Vec<Self::Event>, Self::Error> {
        if cmd.version != self.version {
            return Err(SceneError::ValidationError(
                "Aggregate version mismatch".into(),
            ));
        }
        if self.shooting_day_ids.contains(&cmd.shooting_day_id) {
            // Idempotent push: already scheduled → reject without emitting.
            return Err(SceneError::AlreadyScheduled {
                shooting_day_id: cmd.shooting_day_id,
            });
        }
        let new_version = self.version.next();
        Ok(vec![SceneEvent::ShootingDayScheduled {
            id: self.id,
            shooting_day_id: cmd.shooting_day_id,
            version: new_version,
        }])
    }
}

impl Command<UnscheduleSceneFromShootingDay> for SceneAggregate {
    type Error = SceneError;
    fn handle(
        &self,
        cmd: UnscheduleSceneFromShootingDay,
        _ctx: Context<'_, Self>,
    ) -> Result<Vec<Self::Event>, Self::Error> {
        if cmd.version != self.version {
            return Err(SceneError::ValidationError(
                "Aggregate version mismatch".into(),
            ));
        }
        if !self.shooting_day_ids.contains(&cmd.shooting_day_id) {
            return Err(SceneError::NotScheduled {
                shooting_day_id: cmd.shooting_day_id,
            });
        }
        let new_version = self.version.next();
        Ok(vec![SceneEvent::ShootingDayUnscheduled {
            id: self.id,
            shooting_day_id: cmd.shooting_day_id,
            version: new_version,
        }])
    }
}

// ── Tests ──────────────────────────────────────────────────────────

#[cfg(test)]
#[path = "aggregate_test.rs"]
mod tests;
