// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4-flash (neuralwatt)
// Co-authored-by: mimo-v2.5 (opencode-go)

//! Episode aggregate using `kameo_es` event-sourced actor pattern.

use kameo_es::{Apply, Command, Context, Entity, Metadata};
use uuid::Uuid;

use crate::shared::{AggregateVersion, BlockId, EventMetadata, ProjectId};

use super::commands::{CreateEpisode, DeleteEpisode, RenameEpisode};
use super::error::EpisodeError;
use super::events::EpisodeEvent;

/// State persisted by the Episode aggregate.
///
/// An Episode is scoped to exactly one `BlockId` and is the work-unit scope
/// for Scenes. Its `project_id` is denormalized (immutable for the
/// Episode's lifetime) so the project-global `(project_id, number)` numbering
/// unique index can be enforced directly in the projection.
#[derive(Debug, Clone, Default)]
pub struct EpisodeAggregate {
    pub id: Uuid,
    pub block_id: BlockId,
    pub project_id: ProjectId,
    pub number: i32,
    pub name: Option<String>,
    pub version: AggregateVersion,
}

impl Entity for EpisodeAggregate {
    type ID = Uuid;
    type Event = EpisodeEvent;
    type Metadata = EventMetadata;

    fn category() -> &'static str {
        "episode"
    }
}

// ADR-002 (Event Sourcing / CQRS): Apply replays past events to rebuild
// aggregate state. Every command handler emits events that are applied here.
impl Apply for EpisodeAggregate {
    fn apply(&mut self, event: Self::Event, _metadata: Metadata<EventMetadata>) {
        match event {
            // Issue #770 (dev data reset): the delete carries no further state
            // change — the projector removes the projection row and the stream
            // keeps its history for the audit trail.
            EpisodeEvent::EpisodeDeleted { version, .. } => {
                self.version = version;
            }
            EpisodeEvent::EpisodeCreated {
                id,
                block_id,
                project_id,
                number,
                name,
                version,
            } => {
                self.id = id;
                self.block_id = block_id;
                self.project_id = project_id;
                self.number = number;
                self.name = name;
                self.version = version;
            }
            EpisodeEvent::EpisodeRenamed { name, version, .. } => {
                self.name = name;
                self.version = version;
            }
        }
    }
}

// ADR-002 (Event Sourcing / CQRS): Commands validate invariants and emit
// events. The aggregate state is never mutated directly — only via Apply.
impl Command<CreateEpisode> for EpisodeAggregate {
    type Error = EpisodeError;
    fn handle(
        &self,
        cmd: CreateEpisode,
        _ctx: Context<'_, Self>,
    ) -> Result<Vec<Self::Event>, Self::Error> {
        Ok(vec![EpisodeEvent::EpisodeCreated {
            id: cmd.id,
            block_id: cmd.block_id,
            project_id: cmd.project_id,
            number: cmd.number,
            name: cmd.name,
            version: AggregateVersion::INITIAL,
        }])
    }
}

impl Command<RenameEpisode> for EpisodeAggregate {
    type Error = EpisodeError;
    fn handle(
        &self,
        cmd: RenameEpisode,
        _ctx: Context<'_, Self>,
    ) -> Result<Vec<Self::Event>, Self::Error> {
        if cmd.version != self.version {
            return Err(EpisodeError::VersionMismatch {
                expected: cmd.version,
                actual: self.version,
            });
        }
        if cmd.name == self.name {
            return Err(EpisodeError::ValidationError(
                "Episode name unchanged".into(),
            ));
        }
        let new_version = self.version.next();
        Ok(vec![EpisodeEvent::EpisodeRenamed {
            id: self.id,
            name: cmd.name,
            version: new_version,
        }])
    }
}

// Issue #770 (dev data reset): the delete path for a Episode. See
// `DeleteEpisode` for why it has no HTTP route and no port method.
impl Command<DeleteEpisode> for EpisodeAggregate {
    type Error = EpisodeError;
    fn handle(
        &self,
        cmd: DeleteEpisode,
        _ctx: Context<'_, Self>,
    ) -> Result<Vec<Self::Event>, Self::Error> {
        // An absent aggregate replays to a default state; deleting it must not
        // fabricate a stream. A repeat delete on an existing aggregate is
        // idempotent at the projection (the DELETE matches nothing twice).
        if self.id.is_nil() {
            return Err(EpisodeError::NotFound { id: cmd.id });
        }
        Ok(vec![EpisodeEvent::EpisodeDeleted {
            id: self.id,
            version: self.version.next(),
        }])
    }
}
