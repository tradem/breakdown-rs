// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4-flash (neuralwatt)
// Co-authored-by: mimo-v2.5 (opencode-go)

//! Season aggregate using `kameo_es` event-sourced actor pattern.

use kameo_es::{Apply, Command, Context, Entity, Metadata};
use uuid::Uuid;

use crate::shared::{AggregateVersion, EventMetadata, ProjectId};

use super::commands::{ArchiveSeason, CreateSeason, RenameSeason};
use super::error::SeasonError;
use super::events::SeasonEvent;

/// State persisted by the Season aggregate.
///
/// A Season is scoped to exactly one `ProjectId`. It does NOT own per-Block or
/// per-Episode containment; that is derived from events in the read model.
#[derive(Debug, Clone, Default)]
pub struct SeasonAggregate {
    pub id: Uuid,
    pub project_id: ProjectId,
    pub number: i32,
    pub title: Option<String>,
    pub version: AggregateVersion,
    /// Terminal lifecycle state (issue #533): an archived season keeps its
    /// number reserved and its inventory (blocks/episodes/days) readable, but
    /// rejects further mutation (`RenameSeason`).
    pub archived: bool,
}

impl Entity for SeasonAggregate {
    type ID = Uuid;
    type Event = SeasonEvent;
    type Metadata = EventMetadata;

    fn category() -> &'static str {
        "season"
    }
}

// ADR-002 (Event Sourcing / CQRS): Apply replays past events to rebuild
// aggregate state. Every command handler emits events that are applied here.
impl Apply for SeasonAggregate {
    fn apply(&mut self, event: Self::Event, _metadata: Metadata<EventMetadata>) {
        match event {
            SeasonEvent::SeasonCreated {
                id,
                project_id,
                number,
                title,
                version,
            } => {
                self.id = id;
                self.project_id = project_id;
                self.number = number;
                self.title = title;
                self.version = version;
            }
            SeasonEvent::SeasonRenamed { title, version, .. } => {
                self.title = title;
                self.version = version;
            }
            SeasonEvent::SeasonArchived { version, .. } => {
                self.archived = true;
                self.version = version;
            }
        }
    }
}

// ADR-002 (Event Sourcing / CQRS): Commands validate invariants and emit
// events. The aggregate state is never mutated directly — only via Apply.
impl Command<CreateSeason> for SeasonAggregate {
    type Error = SeasonError;
    fn handle(
        &self,
        cmd: CreateSeason,
        _ctx: Context<'_, Self>,
    ) -> Result<Vec<Self::Event>, Self::Error> {
        // Project-global numbering uniqueness is enforced by a Postgres unique
        // index on (project_id, number) in the projection, NOT here (CQRS
        // write/read split — the aggregate cannot read its siblings).
        Ok(vec![SeasonEvent::SeasonCreated {
            id: cmd.id,
            project_id: cmd.project_id,
            number: cmd.number,
            title: cmd.title,
            version: AggregateVersion::INITIAL,
        }])
    }
}

impl Command<RenameSeason> for SeasonAggregate {
    type Error = SeasonError;
    fn handle(
        &self,
        cmd: RenameSeason,
        _ctx: Context<'_, Self>,
    ) -> Result<Vec<Self::Event>, Self::Error> {
        // Archived-season lock (issue #533): the lifecycle state terminal — no
        // further mutation, only reading stays possible.
        if self.archived {
            return Err(SeasonError::ArchivedCannotBeMutated { id: self.id });
        }
        if cmd.version != self.version {
            return Err(SeasonError::VersionMismatch {
                expected: cmd.version,
                actual: self.version,
            });
        }
        if cmd.title == self.title {
            return Err(SeasonError::ValidationError(
                "Season title unchanged".into(),
            ));
        }
        let new_version = self.version.next();
        Ok(vec![SeasonEvent::SeasonRenamed {
            id: self.id,
            title: cmd.title,
            version: new_version,
        }])
    }
}

impl Command<ArchiveSeason> for SeasonAggregate {
    type Error = SeasonError;
    fn handle(
        &self,
        cmd: ArchiveSeason,
        _ctx: Context<'_, Self>,
    ) -> Result<Vec<Self::Event>, Self::Error> {
        if cmd.version != self.version {
            return Err(SeasonError::VersionMismatch {
                expected: cmd.version,
                actual: self.version,
            });
        }
        // Idempotent-reject: a season that is already archived stays archived
        // and emits no further event (same behaviour as
        // ArchiveCostumeCategory and ArchiveShootingDay).
        if self.archived {
            return Err(SeasonError::ArchivedCannotBeMutated { id: self.id });
        }
        let new_version = self.version.next();
        Ok(vec![SeasonEvent::SeasonArchived {
            id: self.id,
            version: new_version,
        }])
    }
}
