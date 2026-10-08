// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024 Breakdown RS Contributors
// Co-authored-by: deepseek-v4-flash (neuralwatt)
// Co-authored-by: mimo-v2.5 (opencode-go)
// Co-authored-by: longcat-2.0-free (opencode)

//! Scene aggregate using `kameo_es` event-sourced actor pattern.

use kameo_es::{Apply, Command, Context, Entity, Metadata};
use uuid::Uuid;

use crate::shared::{AggregateVersion, EpisodeId, EventMetadata, ShootingDayId};

use super::commands::{
    AddCostumeBeat, AssignCharacter, CreateScene, RemoveCharacter, RemoveCostumeBeat,
    ScheduleSceneOnShootingDay, UnscheduleSceneFromShootingDay, UpdateCostumeBeat,
    UpdateSceneDetails,
};
use super::costume::SceneCostumeBeat;
use super::error::SceneError;
use super::events::SceneEvent;

use crate::scene::events::{SceneDetails, SceneSource};

/// State persisted by the Scene aggregate.
///
/// A Scene references exactly one `EpisodeId` (the work-unit scope). It does
/// NOT carry any production-level scope (Project/Season/Block) directly.
#[derive(Debug, Clone, Default)]
pub struct SceneAggregate {
    pub id: Uuid,
    pub episode_id: EpisodeId,
    pub details: SceneDetails,
    pub assigned_characters: Vec<Uuid>,
    /// Shooting days this scene is linked to (the scene owns the collection).
    pub shooting_day_ids: Vec<ShootingDayId>,
    /// Ordered costume beats per (character, order) — the scene-side
    /// casting relation (issue #546). Legacy streams replay with an empty
    /// list.
    pub costume_beats: Vec<SceneCostumeBeat>,
    /// Provenance discriminator (Manual | AiExtracted); see `SceneSource`.
    pub source: SceneSource,
    pub version: AggregateVersion,
}

impl Entity for SceneAggregate {
    type ID = Uuid;
    type Event = SceneEvent;
    type Metadata = EventMetadata;

    fn category() -> &'static str {
        "scene"
    }
}

// ADR-002 (Event Sourcing / CQRS): Apply replays past events to rebuild
// aggregate state. Every command handler emits events that are applied here.
impl Apply for SceneAggregate {
    fn apply(&mut self, event: Self::Event, _metadata: Metadata<EventMetadata>) {
        match event {
            SceneEvent::SceneCreated {
                id,
                episode_id,
                details,
                assigned_characters,
                source,
                version,
            } => {
                self.id = id;
                self.episode_id = episode_id;
                self.details = details;
                self.assigned_characters = assigned_characters;
                self.source = source;
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
            SceneEvent::CostumeBeatAdded {
                character_id,
                costume_id,
                order,
                note,
                version,
                ..
            } => {
                self.costume_beats.push(SceneCostumeBeat {
                    character_id,
                    costume_id,
                    order,
                    note,
                });
                self.version = version;
            }
            SceneEvent::CostumeBeatUpdated {
                character_id,
                order,
                costume_id,
                note,
                version,
                ..
            } => {
                if let Some(beat) = self
                    .costume_beats
                    .iter_mut()
                    .find(|b| b.character_id == character_id && b.order == order)
                {
                    beat.costume_id = costume_id;
                    beat.note = note;
                }
                self.version = version;
            }
            SceneEvent::CostumeBeatRemoved {
                character_id,
                order,
                version,
                ..
            } => {
                self.costume_beats
                    .retain(|b| !(b.character_id == character_id && b.order == order));
                self.version = version;
            }
            SceneEvent::CostumeBeatsCleared {
                character_id,
                version,
                ..
            } => {
                self.costume_beats
                    .retain(|b| b.character_id != character_id);
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
            source: cmd.source,
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
            return Err(SceneError::VersionMismatch {
                expected: cmd.version,
                actual: self.version,
            });
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
            return Err(SceneError::VersionMismatch {
                expected: cmd.version,
                actual: self.version,
            });
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
            return Err(SceneError::VersionMismatch {
                expected: cmd.version,
                actual: self.version,
            });
        }
        if !self.assigned_characters.contains(&cmd.character_id) {
            return Err(SceneError::ValidationError(
                "Character is not assigned to this scene".into(),
            ));
        }
        let mut v = self.version;
        let mut events = Vec::new();
        // Issue #546 (CodeRabbit review): a character with costume beats must
        // not leave orphan beats behind — after `CharacterRemoved` every beat
        // command would fail `CharacterNotInScene`, making the beats
        // unreachable. Clear them first, then remove the character; both
        // events advance the version in order.
        if self
            .costume_beats
            .iter()
            .any(|b| b.character_id == cmd.character_id)
        {
            v = v.next();
            events.push(SceneEvent::CostumeBeatsCleared {
                id: self.id,
                character_id: cmd.character_id,
                version: v,
            });
        }
        v = v.next();
        events.push(SceneEvent::CharacterRemoved {
            id: self.id,
            character_id: cmd.character_id,
            version: v,
        });
        Ok(events)
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
            return Err(SceneError::VersionMismatch {
                expected: cmd.version,
                actual: self.version,
            });
        }
        if self.shooting_day_ids.contains(&cmd.shooting_day_id) {
            // Defensive guard: unreachable through the command service, which
            // consults `is_state_idempotent` first and short-circuits to
            // `ExecuteResult::Idempotent`. Kept so a direct `handle` call (the
            // `core` unit tests) still honours "emit no duplicate event".
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

    /// Scheduling a day the scene already links is a no-op, not a conflict.
    ///
    /// `kameo_es` turns this into `ExecuteResult::Idempotent { current_version }`,
    /// which the command adapter maps to the current aggregate version. That is
    /// what makes a retried AI schedule-apply converge: after a crash between
    /// the event append and the idempotency-mapping write, the retry re-dispatches
    /// this command and must get the version back rather than a permanent
    /// `Conflict` that strands the mapping (issue #179).
    ///
    /// Optimistic concurrency is unaffected: the actor validates
    /// `ExpectedVersion` against the stream *before* consulting this hook, so a
    /// stale command still fails with a version conflict.
    fn is_state_idempotent(
        &self,
        cmd: &ScheduleSceneOnShootingDay,
        _ctx: Context<'_, Self>,
    ) -> bool {
        self.shooting_day_ids.contains(&cmd.shooting_day_id)
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
            return Err(SceneError::VersionMismatch {
                expected: cmd.version,
                actual: self.version,
            });
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

impl Command<AddCostumeBeat> for SceneAggregate {
    type Error = SceneError;
    fn handle(
        &self,
        cmd: AddCostumeBeat,
        _ctx: Context<'_, Self>,
    ) -> Result<Vec<Self::Event>, Self::Error> {
        if cmd.version != self.version {
            return Err(SceneError::VersionMismatch {
                expected: cmd.version,
                actual: self.version,
            });
        }
        if !self.assigned_characters.contains(&cmd.character_id) {
            return Err(SceneError::CharacterNotInScene {
                character_id: cmd.character_id,
            });
        }
        // `order` is aggregate-computed (max + 1, dense zero-based): a
        // client-chosen order is a race.
        let order = self
            .costume_beats
            .iter()
            .filter(|b| b.character_id == cmd.character_id)
            .map(|b| b.order)
            .max()
            .map_or(0, |max| max + 1);
        // Consecutive-identical-beat guard: appending the costume the
        // character already wears last is virtually always a user error
        // ("on change, then straight back on"); the crew does not need that
        // state in the data.
        let identical_last = self
            .costume_beats
            .iter()
            .filter(|b| b.character_id == cmd.character_id)
            .max_by_key(|b| b.order)
            .is_some_and(|last| last.costume_id == cmd.costume_id && last.note == cmd.note);
        if identical_last {
            return Err(SceneError::ValidationError(
                "Costume beat identical to the character's last beat".into(),
            ));
        }
        let new_version = self.version.next();
        Ok(vec![SceneEvent::CostumeBeatAdded {
            id: self.id,
            character_id: cmd.character_id,
            costume_id: cmd.costume_id,
            order,
            note: cmd.note,
            version: new_version,
        }])
    }
}

impl Command<UpdateCostumeBeat> for SceneAggregate {
    type Error = SceneError;
    fn handle(
        &self,
        cmd: UpdateCostumeBeat,
        _ctx: Context<'_, Self>,
    ) -> Result<Vec<Self::Event>, Self::Error> {
        if cmd.version != self.version {
            return Err(SceneError::VersionMismatch {
                expected: cmd.version,
                actual: self.version,
            });
        }
        if !self.assigned_characters.contains(&cmd.character_id) {
            return Err(SceneError::CharacterNotInScene {
                character_id: cmd.character_id,
            });
        }
        if !self
            .costume_beats
            .iter()
            .any(|b| b.character_id == cmd.character_id && b.order == cmd.order)
        {
            return Err(SceneError::BeatNotFound {
                character_id: cmd.character_id,
                order: cmd.order,
            });
        }
        let new_version = self.version.next();
        Ok(vec![SceneEvent::CostumeBeatUpdated {
            id: self.id,
            character_id: cmd.character_id,
            order: cmd.order,
            costume_id: cmd.costume_id,
            note: cmd.note,
            version: new_version,
        }])
    }
}

impl Command<RemoveCostumeBeat> for SceneAggregate {
    type Error = SceneError;
    fn handle(
        &self,
        cmd: RemoveCostumeBeat,
        _ctx: Context<'_, Self>,
    ) -> Result<Vec<Self::Event>, Self::Error> {
        if cmd.version != self.version {
            return Err(SceneError::VersionMismatch {
                expected: cmd.version,
                actual: self.version,
            });
        }
        if !self.assigned_characters.contains(&cmd.character_id) {
            return Err(SceneError::CharacterNotInScene {
                character_id: cmd.character_id,
            });
        }
        let has_beats = self
            .costume_beats
            .iter()
            .any(|b| b.character_id == cmd.character_id);
        match cmd.order {
            Some(order) => {
                if !self
                    .costume_beats
                    .iter()
                    .any(|b| b.character_id == cmd.character_id && b.order == order)
                {
                    return Err(SceneError::BeatNotFound {
                        character_id: cmd.character_id,
                        order,
                    });
                }
                let new_version = self.version.next();
                Ok(vec![SceneEvent::CostumeBeatRemoved {
                    id: self.id,
                    character_id: cmd.character_id,
                    order,
                    version: new_version,
                }])
            }
            None => {
                if !has_beats {
                    return Err(SceneError::NoCostumeBeats {
                        character_id: cmd.character_id,
                    });
                }
                let new_version = self.version.next();
                Ok(vec![SceneEvent::CostumeBeatsCleared {
                    id: self.id,
                    character_id: cmd.character_id,
                    version: new_version,
                }])
            }
        }
    }
}
