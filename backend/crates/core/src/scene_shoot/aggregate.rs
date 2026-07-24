// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4-flash (opencode-go)

//! The `SceneShoot` event-sourced aggregate.

use chrono::{DateTime, Utc};
use kameo_es::{Apply, Command, Context, Entity, Metadata};
use uuid::Uuid;

use crate::shared::{
    AggregateVersion, LexicalSortKey, PhotoId, SceneShootId, SceneShootStatus, ShootingDayId,
};

use super::commands::{
    AddSceneShootNote, FinishSceneShoot, LinkContinuityPhoto, PlanSceneShoot, RemoveSceneShootNote,
    ReplanSceneShoot, SetActualOrder, SkipSceneShoot, StartSceneShoot, UnlinkContinuityPhoto,
    UpdateSceneShootNote,
};
use super::error::SceneShootError;
use super::events::{SceneShootEvent, SceneShootNote};

/// State persisted by the `SceneShoot` aggregate.
///
/// A `SceneShoot` models the association between a `Scene` and a
/// `ShootingDay`, carrying both planned (Dispo / Soll) and actual (Ist)
/// execution data. Each `(scene_id, shooting_day_id)` pair gets its own
/// event-sourced stream.
#[derive(Debug, Clone)]
pub struct SceneShootAggregate {
    pub id: SceneShootId,
    pub scene_id: Uuid,
    pub shooting_day_id: ShootingDayId,
    pub planned_order: LexicalSortKey,
    pub actual_order: Option<LexicalSortKey>,
    pub status: SceneShootStatus,
    pub start_dt: Option<DateTime<Utc>>,
    pub end_dt: Option<DateTime<Utc>>,
    pub notes: Vec<SceneShootNote>,
    pub continuity_photos: Vec<PhotoId>,
    pub version: AggregateVersion,
}

impl Default for SceneShootAggregate {
    fn default() -> Self {
        Self {
            id: SceneShootId::default(),
            scene_id: Uuid::default(),
            shooting_day_id: ShootingDayId::default(),
            planned_order: LexicalSortKey::from_static("0"),
            actual_order: None,
            status: SceneShootStatus::Planned,
            start_dt: None,
            end_dt: None,
            notes: Vec::new(),
            continuity_photos: Vec::new(),
            version: AggregateVersion::default(),
        }
    }
}

impl Entity for SceneShootAggregate {
    type ID = SceneShootId;
    type Event = SceneShootEvent;
    type Metadata = ();

    fn category() -> &'static str {
        "scene_shoot"
    }
}

impl SceneShootAggregate {
    /// Returns `true` if execution data has been recorded on this scene shoot
    /// (either `actual_order` is set or `start_dt` is set).
    fn has_execution_data(&self) -> bool {
        self.actual_order.is_some() || self.start_dt.is_some()
    }

    /// Returns `true` if the scene shoot is in a terminal state (Shot or Skipped).
    fn is_terminal(&self) -> bool {
        matches!(self.status, SceneShootStatus::Shot | SceneShootStatus::Skipped)
    }

    fn check_not_terminal(&self) -> Result<(), SceneShootError> {
        if self.is_terminal() {
            return Err(SceneShootError::TerminalState {
                status: self.status,
            });
        }
        Ok(())
    }

    fn check_version(&self, expected: AggregateVersion) -> Result<(), SceneShootError> {
        if expected != self.version {
            return Err(SceneShootError::VersionMismatch {
                entity: "SceneShoot".into(),
                expected,
                actual: self.version,
            });
        }
        Ok(())
    }

    /// Returns the next version, incrementing from the current state.
    fn next_version(&self) -> AggregateVersion {
        self.version.next()
    }

    /// Returns the new status when execution data is introduced.
    /// If currently Planned/Scheduled, transitions to InProgress.
    fn transition_on_execution(&self) -> SceneShootStatus {
        if matches!(
            self.status,
            SceneShootStatus::Planned | SceneShootStatus::Scheduled
        ) {
            SceneShootStatus::InProgress
        } else {
            self.status
        }
    }
}

impl Apply for SceneShootAggregate {
    fn apply(&mut self, event: Self::Event, _metadata: Metadata<()>) {
        match event {
            SceneShootEvent::SceneShootPlanned {
                id,
                scene_id,
                shooting_day_id,
                planned_order,
                status,
                version,
            } => {
                self.id = id;
                self.scene_id = scene_id;
                self.shooting_day_id = shooting_day_id;
                self.planned_order = planned_order;
                self.status = status;
                self.actual_order = None;
                self.start_dt = None;
                self.end_dt = None;
                self.notes = Vec::new();
                self.continuity_photos = Vec::new();
                self.version = version;
            }
            SceneShootEvent::SceneShootReplanned {
                planned_order, version, ..
            } => {
                self.planned_order = planned_order;
                self.version = version;
            }
            SceneShootEvent::SceneShootStarted { start_dt, version, .. } => {
                self.start_dt = Some(start_dt);
                self.status = self.transition_on_execution();
                self.version = version;
            }
            SceneShootEvent::SceneShootActualOrderSet {
                actual_order, version, ..
            } => {
                self.actual_order = Some(actual_order);
                self.status = self.transition_on_execution();
                self.version = version;
            }
            SceneShootEvent::SceneShootFinished { end_dt, version, .. } => {
                self.end_dt = Some(end_dt);
                self.status = SceneShootStatus::Shot;
                self.version = version;
            }
            SceneShootEvent::SceneShootSkipped { version, .. } => {
                self.status = SceneShootStatus::Skipped;
                self.version = version;
            }
            SceneShootEvent::ShootDayNoteAdded {
                note_id,
                body,
                author,
                version,
                ..
            } => {
                self.notes.push(SceneShootNote {
                    id: note_id,
                    body,
                    author,
                });
                self.version = version;
            }
            SceneShootEvent::ShootDayNoteUpdated {
                note_id, body, version, ..
            } => {
                if let Some(note) = self.notes.iter_mut().find(|n| n.id == note_id) {
                    note.body = body;
                }
                self.version = version;
            }
            SceneShootEvent::ShootDayNoteRemoved { note_id, version, .. } => {
                self.notes.retain(|n| n.id != note_id);
                self.version = version;
            }
            SceneShootEvent::ContinuityPhotoLinked { photo_id, version, .. } => {
                self.continuity_photos.push(photo_id);
                self.version = version;
            }
            SceneShootEvent::ContinuityPhotoUnlinked { photo_id, version, .. } => {
                self.continuity_photos.retain(|p| *p != photo_id);
                self.version = version;
            }
        }
    }
}

impl Command<PlanSceneShoot> for SceneShootAggregate {
    type Error = SceneShootError;

    fn handle(
        &self,
        cmd: PlanSceneShoot,
        _ctx: Context<'_, Self>,
    ) -> Result<Vec<Self::Event>, Self::Error> {
        // Pair-uniqueness: on a fresh (never-before-seen) stream the aggregate will be
        // in its `Default` state with `scene_id = Uuid::nil()`. After replaying a
        // `SceneShootPlanned` event, `scene_id` will be set to a non-nil value.
        if !self.scene_id.is_nil() {
            return Err(SceneShootError::PairAlreadyExists);
        }

        Ok(vec![SceneShootEvent::SceneShootPlanned {
            id: cmd.id,
            scene_id: cmd.scene_id,
            shooting_day_id: cmd.shooting_day_id,
            planned_order: cmd.planned_order,
            status: SceneShootStatus::Planned,
            version: AggregateVersion::INITIAL,
        }])
    }
}

impl Command<ReplanSceneShoot> for SceneShootAggregate {
    type Error = SceneShootError;

    fn handle(
        &self,
        cmd: ReplanSceneShoot,
        _ctx: Context<'_, Self>,
    ) -> Result<Vec<Self::Event>, Self::Error> {
        self.check_not_terminal()?;
        self.check_version(cmd.version)?;

        // Reject if execution data has been recorded (passive freeze).
        if self.has_execution_data() {
            return Err(SceneShootError::PlannedOrderFrozen);
        }

        let new_version = self.next_version();
        Ok(vec![SceneShootEvent::SceneShootReplanned {
            id: self.id,
            planned_order: cmd.planned_order,
            version: new_version,
        }])
    }
}

impl Command<StartSceneShoot> for SceneShootAggregate {
    type Error = SceneShootError;

    fn handle(
        &self,
        cmd: StartSceneShoot,
        _ctx: Context<'_, Self>,
    ) -> Result<Vec<Self::Event>, Self::Error> {
        self.check_not_terminal()?;
        self.check_version(cmd.version)?;

        // Idempotent: re-dispatch with the same start_dt is a no-op.
        if self.start_dt == Some(cmd.start_dt) {
            return Ok(vec![]);
        }

        // Reject if already started with a different start_dt.
        if self.start_dt.is_some() {
            return Err(SceneShootError::AlreadyStarted);
        }

        let new_version = self.next_version();
        Ok(vec![SceneShootEvent::SceneShootStarted {
            id: self.id,
            start_dt: cmd.start_dt,
            version: new_version,
        }])
    }
}

impl Command<SetActualOrder> for SceneShootAggregate {
    type Error = SceneShootError;

    fn handle(
        &self,
        cmd: SetActualOrder,
        _ctx: Context<'_, Self>,
    ) -> Result<Vec<Self::Event>, Self::Error> {
        self.check_not_terminal()?;
        self.check_version(cmd.version)?;

        let new_version = self.next_version();
        Ok(vec![SceneShootEvent::SceneShootActualOrderSet {
            id: self.id,
            actual_order: cmd.actual_order,
            version: new_version,
        }])
    }
}

impl Command<FinishSceneShoot> for SceneShootAggregate {
    type Error = SceneShootError;

    fn handle(
        &self,
        cmd: FinishSceneShoot,
        _ctx: Context<'_, Self>,
    ) -> Result<Vec<Self::Event>, Self::Error> {
        self.check_not_terminal()?;
        self.check_version(cmd.version)?;

        // Must at least be InProgress to finish.
        if self.status != SceneShootStatus::InProgress {
            return Err(SceneShootError::ValidationError(
                "Can only finish a SceneShoot that is InProgress".into(),
            ));
        }

        let new_version = self.next_version();
        Ok(vec![SceneShootEvent::SceneShootFinished {
            id: self.id,
            end_dt: cmd.end_dt,
            version: new_version,
        }])
    }
}

impl Command<SkipSceneShoot> for SceneShootAggregate {
    type Error = SceneShootError;

    fn handle(
        &self,
        cmd: SkipSceneShoot,
        _ctx: Context<'_, Self>,
    ) -> Result<Vec<Self::Event>, Self::Error> {
        self.check_not_terminal()?;
        self.check_version(cmd.version)?;

        let new_version = self.next_version();
        Ok(vec![SceneShootEvent::SceneShootSkipped {
            id: self.id,
            version: new_version,
        }])
    }
}

impl Command<AddSceneShootNote> for SceneShootAggregate {
    type Error = SceneShootError;

    fn handle(
        &self,
        cmd: AddSceneShootNote,
        _ctx: Context<'_, Self>,
    ) -> Result<Vec<Self::Event>, Self::Error> {
        self.check_not_terminal()?;

        let new_version = self.next_version();
        Ok(vec![SceneShootEvent::ShootDayNoteAdded {
            id: self.id,
            note_id: cmd.note_id,
            body: cmd.body,
            author: cmd.author,
            version: new_version,
        }])
    }
}

impl Command<UpdateSceneShootNote> for SceneShootAggregate {
    type Error = SceneShootError;

    fn handle(
        &self,
        cmd: UpdateSceneShootNote,
        _ctx: Context<'_, Self>,
    ) -> Result<Vec<Self::Event>, Self::Error> {
        self.check_not_terminal()?;
        self.check_version(cmd.version)?;

        if !self.notes.iter().any(|n| n.id == cmd.note_id) {
            return Err(SceneShootError::NoteNotFound {
                note_id: cmd.note_id,
            });
        }

        let new_version = self.next_version();
        Ok(vec![SceneShootEvent::ShootDayNoteUpdated {
            id: self.id,
            note_id: cmd.note_id,
            body: cmd.body,
            version: new_version,
        }])
    }
}

impl Command<RemoveSceneShootNote> for SceneShootAggregate {
    type Error = SceneShootError;

    fn handle(
        &self,
        cmd: RemoveSceneShootNote,
        _ctx: Context<'_, Self>,
    ) -> Result<Vec<Self::Event>, Self::Error> {
        self.check_not_terminal()?;
        self.check_version(cmd.version)?;

        if !self.notes.iter().any(|n| n.id == cmd.note_id) {
            return Err(SceneShootError::NoteNotFound {
                note_id: cmd.note_id,
            });
        }

        let new_version = self.next_version();
        Ok(vec![SceneShootEvent::ShootDayNoteRemoved {
            id: self.id,
            note_id: cmd.note_id,
            version: new_version,
        }])
    }
}

impl Command<LinkContinuityPhoto> for SceneShootAggregate {
    type Error = SceneShootError;

    fn handle(
        &self,
        cmd: LinkContinuityPhoto,
        _ctx: Context<'_, Self>,
    ) -> Result<Vec<Self::Event>, Self::Error> {
        self.check_not_terminal()?;
        self.check_version(cmd.version)?;

        if self.continuity_photos.contains(&cmd.photo_id) {
            return Err(SceneShootError::AlreadyLinked {
                photo_id: cmd.photo_id,
            });
        }

        let new_version = self.next_version();
        Ok(vec![SceneShootEvent::ContinuityPhotoLinked {
            id: self.id,
            photo_id: cmd.photo_id,
            version: new_version,
        }])
    }
}

impl Command<UnlinkContinuityPhoto> for SceneShootAggregate {
    type Error = SceneShootError;

    fn handle(
        &self,
        cmd: UnlinkContinuityPhoto,
        _ctx: Context<'_, Self>,
    ) -> Result<Vec<Self::Event>, Self::Error> {
        self.check_not_terminal()?;
        self.check_version(cmd.version)?;

        let new_version = self.next_version();
        Ok(vec![SceneShootEvent::ContinuityPhotoUnlinked {
            id: self.id,
            photo_id: cmd.photo_id,
            version: new_version,
        }])
    }
}

#[cfg(test)]
#[path = "aggregate_test.rs"]
mod tests;
