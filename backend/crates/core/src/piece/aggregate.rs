// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

//! The `Piece` aggregate — one garment in the wardrobe fundus.
//!
//! State is rebuilt exclusively from [`PieceEvent`]s; commands validate the
//! aggregate-local invariants (non-blank name, version fence, detail identity,
//! state-based no-ops) and emit events. Cross-aggregate facts (category season
//! membership, season existence/archived state, outfit membership) are
//! API-edge pre-checks and never block replay.

use kameo_es::{Apply, Command, Context, Entity, Metadata};
use uuid::Uuid;

use crate::shared::{AggregateVersion, CostumeCategoryId, EventMetadata, SeasonId};

use super::commands::*;
use super::error::PieceError;
use super::events::*;

/// State persisted by the `Piece` aggregate.
///
/// Deliberately **character-free**: the character binding lives on the
/// `Outfit` aggregate. A piece's only scope relation is its season repertoire.
#[derive(Debug, Clone, Default)]
pub struct PieceAggregate {
    pub id: Uuid,
    /// Required, non-blank display name ("Rote Lederjacke"). Not unique.
    pub name: String,
    /// The piece's single category (n:1 into the season-scoped
    /// `CostumeCategory` vocabulary). `None` = uncategorised.
    pub category_id: Option<CostumeCategoryId>,
    /// The piece's season **repertoire**: the seasons whose wardrobe lists the
    /// piece appears in. m:n over its lifetime; ordered by binding time, no
    /// duplicates.
    pub seasons: Vec<SeasonId>,
    pub notes: String,
    pub details: Vec<PieceDetail>,
    pub photos: Vec<Uuid>,
    pub version: AggregateVersion,
}

/// Trim a name and reject the blank case (422 `piece.validation`).
fn normalize_name(raw: &str) -> Result<String, PieceError> {
    let trimmed = raw.trim();
    if trimmed.is_empty() {
        return Err(PieceError::EmptyName);
    }
    Ok(trimmed.to_string())
}

impl Entity for PieceAggregate {
    type ID = Uuid;
    type Event = PieceEvent;
    type Metadata = EventMetadata;

    fn category() -> &'static str {
        "piece"
    }
}

impl Apply for PieceAggregate {
    fn apply(&mut self, event: Self::Event, _metadata: Metadata<EventMetadata>) {
        match event {
            // Issue #770 (dev data reset): the delete carries no further state
            // change — the projector removes the projection row and the stream
            // keeps its history for the audit trail.
            PieceEvent::PieceDeleted { version, .. } => {
                self.version = version;
            }
            PieceEvent::PieceCreated {
                id,
                name,
                category_id,
                season_id,
                notes,
                details,
                photos,
                version,
            } => {
                self.id = id;
                self.name = name;
                self.category_id = category_id;
                self.seasons = season_id.map(SeasonId).into_iter().collect();
                self.notes = notes;
                self.details = details;
                self.photos = photos;
                self.version = version;
            }
            PieceEvent::PieceRenamed { name, version, .. } => {
                self.name = name;
                self.version = version;
            }
            PieceEvent::PieceNotesUpdated { notes, version, .. } => {
                self.notes = notes;
                self.version = version;
            }
            PieceEvent::PieceAddedToSeason {
                season_id, version, ..
            } => {
                let season_id = SeasonId(season_id);
                if !self.seasons.contains(&season_id) {
                    self.seasons.push(season_id);
                }
                self.version = version;
            }
            PieceEvent::PieceRemovedFromSeason {
                season_id, version, ..
            } => {
                let season_id = SeasonId(season_id);
                self.seasons.retain(|s| *s != season_id);
                self.version = version;
            }
            PieceEvent::PieceDetailAdded {
                detail, version, ..
            } => {
                self.details.push(detail);
                self.version = version;
            }
            PieceEvent::PieceDetailUpdated {
                detail, version, ..
            } => {
                if let Some(existing) = self.details.iter_mut().find(|d| d.id == detail.id) {
                    *existing = detail;
                } else {
                    self.details.push(detail);
                }
                self.version = version;
            }
            PieceEvent::PieceDetailRemoved {
                detail_id, version, ..
            } => {
                self.details.retain(|d| d.id != detail_id);
                self.version = version;
            }
            PieceEvent::PieceCategorySet {
                category_id,
                version,
                ..
            } => {
                self.category_id = category_id;
                self.version = version;
            }
            PieceEvent::PiecePhotoLinked {
                photo_id, version, ..
            } => {
                if !self.photos.contains(&photo_id) {
                    self.photos.push(photo_id);
                }
                self.version = version;
            }
            PieceEvent::PiecePhotoUnlinked {
                photo_id, version, ..
            } => {
                self.photos.retain(|&id| id != photo_id);
                self.version = version;
            }
        }
    }
}

// ADR-002 (Event Sourcing / CQRS): commands validate invariants and emit
// events. Aggregate state is mutated only through `Apply`.
impl Command<CreatePiece> for PieceAggregate {
    type Error = PieceError;
    fn handle(
        &self,
        cmd: CreatePiece,
        _ctx: Context<'_, Self>,
    ) -> Result<Vec<Self::Event>, Self::Error> {
        let name = normalize_name(&cmd.name)?;
        Ok(vec![PieceEvent::PieceCreated {
            id: cmd.id,
            name,
            category_id: cmd.category_id,
            season_id: cmd.season_id.map(|s| s.0),
            notes: String::new(),
            details: Vec::new(),
            photos: Vec::new(),
            version: AggregateVersion::INITIAL,
        }])
    }
}

impl Command<RenamePiece> for PieceAggregate {
    type Error = PieceError;
    fn handle(
        &self,
        cmd: RenamePiece,
        _ctx: Context<'_, Self>,
    ) -> Result<Vec<Self::Event>, Self::Error> {
        if cmd.version != self.version {
            return Err(PieceError::VersionMismatch {
                expected: cmd.version,
                actual: self.version,
            });
        }
        let name = normalize_name(&cmd.name)?;
        // State-based no-op: renaming to the identical name emits nothing.
        if name == self.name {
            return Ok(vec![]);
        }
        Ok(vec![PieceEvent::PieceRenamed {
            id: self.id,
            name,
            version: self.version.next(),
        }])
    }
}

impl Command<UpdatePieceNotes> for PieceAggregate {
    type Error = PieceError;
    fn handle(
        &self,
        cmd: UpdatePieceNotes,
        _ctx: Context<'_, Self>,
    ) -> Result<Vec<Self::Event>, Self::Error> {
        if cmd.version != self.version {
            return Err(PieceError::VersionMismatch {
                expected: cmd.version,
                actual: self.version,
            });
        }
        if cmd.notes == self.notes {
            return Err(PieceError::ValidationError("Notes unchanged".into()));
        }
        Ok(vec![PieceEvent::PieceNotesUpdated {
            id: self.id,
            notes: cmd.notes,
            version: self.version.next(),
        }])
    }
}

impl Command<AddPieceToSeason> for PieceAggregate {
    type Error = PieceError;
    fn handle(
        &self,
        cmd: AddPieceToSeason,
        _ctx: Context<'_, Self>,
    ) -> Result<Vec<Self::Event>, Self::Error> {
        if cmd.version != self.version {
            return Err(PieceError::VersionMismatch {
                expected: cmd.version,
                actual: self.version,
            });
        }
        // State-based no-op (issue #515 precedent): adding a season the piece
        // already stands in emits no event. The target season's existence and
        // not-archived state are API-edge pre-checks (404 `season.not-found` /
        // 409 `season.archived`); the aggregate cannot validate them.
        if self.seasons.contains(&cmd.season_id) {
            return Ok(vec![]);
        }
        Ok(vec![PieceEvent::PieceAddedToSeason {
            id: self.id,
            season_id: cmd.season_id.0,
            version: self.version.next(),
        }])
    }
}

impl Command<RemovePieceFromSeason> for PieceAggregate {
    type Error = PieceError;
    fn handle(
        &self,
        cmd: RemovePieceFromSeason,
        _ctx: Context<'_, Self>,
    ) -> Result<Vec<Self::Event>, Self::Error> {
        if cmd.version != self.version {
            return Err(PieceError::VersionMismatch {
                expected: cmd.version,
                actual: self.version,
            });
        }
        if !self.seasons.contains(&cmd.season_id) {
            return Ok(vec![]);
        }
        Ok(vec![PieceEvent::PieceRemovedFromSeason {
            id: self.id,
            season_id: cmd.season_id.0,
            version: self.version.next(),
        }])
    }
}

impl Command<AddPieceDetail> for PieceAggregate {
    type Error = PieceError;
    fn handle(
        &self,
        cmd: AddPieceDetail,
        _ctx: Context<'_, Self>,
    ) -> Result<Vec<Self::Event>, Self::Error> {
        if cmd.version != self.version {
            return Err(PieceError::VersionMismatch {
                expected: cmd.version,
                actual: self.version,
            });
        }
        Ok(vec![PieceEvent::PieceDetailAdded {
            id: self.id,
            detail: cmd.detail,
            version: self.version.next(),
        }])
    }
}

impl Command<UpdatePieceDetail> for PieceAggregate {
    type Error = PieceError;
    fn handle(
        &self,
        cmd: UpdatePieceDetail,
        _ctx: Context<'_, Self>,
    ) -> Result<Vec<Self::Event>, Self::Error> {
        if cmd.version != self.version {
            return Err(PieceError::VersionMismatch {
                expected: cmd.version,
                actual: self.version,
            });
        }
        // The reason a partial-update design was rejected: an unknown
        // `detail_id` errors **without** an event, so a typo cannot silently
        // create a second detail.
        if !self.details.iter().any(|d| d.id == cmd.detail.id) {
            return Err(PieceError::DetailNotFound { id: cmd.detail.id });
        }
        Ok(vec![PieceEvent::PieceDetailUpdated {
            id: self.id,
            detail: cmd.detail,
            version: self.version.next(),
        }])
    }
}

impl Command<RemovePieceDetail> for PieceAggregate {
    type Error = PieceError;
    fn handle(
        &self,
        cmd: RemovePieceDetail,
        _ctx: Context<'_, Self>,
    ) -> Result<Vec<Self::Event>, Self::Error> {
        if cmd.version != self.version {
            return Err(PieceError::VersionMismatch {
                expected: cmd.version,
                actual: self.version,
            });
        }
        if !self.details.iter().any(|d| d.id == cmd.detail_id) {
            return Err(PieceError::DetailNotFound { id: cmd.detail_id });
        }
        Ok(vec![PieceEvent::PieceDetailRemoved {
            id: self.id,
            detail_id: cmd.detail_id,
            version: self.version.next(),
        }])
    }
}

impl Command<SetPieceCategory> for PieceAggregate {
    type Error = PieceError;
    fn handle(
        &self,
        cmd: SetPieceCategory,
        _ctx: Context<'_, Self>,
    ) -> Result<Vec<Self::Event>, Self::Error> {
        if cmd.version != self.version {
            return Err(PieceError::VersionMismatch {
                expected: cmd.version,
                actual: self.version,
            });
        }
        // State-based no-op (issue #515 precedent): setting the category the
        // piece already carries (or clearing an already-empty one) emits no
        // event. The season invariant (category season ∈ repertoire) is an
        // API-edge pre-check (409 costume-category.season-mismatch).
        if self.category_id == cmd.category_id {
            return Ok(vec![]);
        }
        Ok(vec![PieceEvent::PieceCategorySet {
            id: self.id,
            category_id: cmd.category_id,
            version: self.version.next(),
        }])
    }
}

impl Command<LinkPiecePhoto> for PieceAggregate {
    type Error = PieceError;
    fn handle(
        &self,
        cmd: LinkPiecePhoto,
        _ctx: Context<'_, Self>,
    ) -> Result<Vec<Self::Event>, Self::Error> {
        if cmd.version != self.version {
            return Err(PieceError::VersionMismatch {
                expected: cmd.version,
                actual: self.version,
            });
        }
        if self.photos.contains(&cmd.photo_id) {
            return Err(PieceError::ValidationError("Photo already linked".into()));
        }
        Ok(vec![PieceEvent::PiecePhotoLinked {
            id: self.id,
            photo_id: cmd.photo_id,
            version: self.version.next(),
        }])
    }
}

impl Command<UnlinkPiecePhoto> for PieceAggregate {
    type Error = PieceError;
    fn handle(
        &self,
        cmd: UnlinkPiecePhoto,
        _ctx: Context<'_, Self>,
    ) -> Result<Vec<Self::Event>, Self::Error> {
        if cmd.version != self.version {
            return Err(PieceError::VersionMismatch {
                expected: cmd.version,
                actual: self.version,
            });
        }
        if !self.photos.contains(&cmd.photo_id) {
            return Err(PieceError::ValidationError("Photo is not linked".into()));
        }
        Ok(vec![PieceEvent::PiecePhotoUnlinked {
            id: self.id,
            photo_id: cmd.photo_id,
            version: self.version.next(),
        }])
    }
}

// Issue #770 (dev data reset): the delete path for a Piece. See
// `DeletePiece` for why it has no HTTP route and no port method.
impl Command<DeletePiece> for PieceAggregate {
    type Error = PieceError;
    fn handle(
        &self,
        cmd: DeletePiece,
        _ctx: Context<'_, Self>,
    ) -> Result<Vec<Self::Event>, Self::Error> {
        // An absent aggregate replays to a default state; deleting it must not
        // fabricate a stream. A repeat delete on an existing aggregate is
        // idempotent at the projection (the DELETE matches nothing twice).
        if self.id.is_nil() {
            return Err(PieceError::NotFound { id: cmd.id });
        }
        Ok(vec![PieceEvent::PieceDeleted {
            id: self.id,
            version: self.version.next(),
        }])
    }
}
