// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024 Breakdown RS Contributors

//! Costume aggregate.

use kameo_es::{Apply, Command, Context, Entity, Metadata};
use uuid::Uuid;

use crate::shared::{AggregateVersion, ProjectId};

use super::commands::*;
use super::error::CostumeError;
use super::events::*;

/// State persisted by the Costume aggregate.
#[derive(Debug, Clone, Default)]
pub struct CostumeAggregate {
    pub id: Uuid,
    pub project_id: ProjectId,
    pub character_id: Option<Uuid>,
    pub notes: String,
    pub details: Vec<CostumeDetail>,
    pub photos: Vec<Uuid>,
    pub version: AggregateVersion,
}

impl Entity for CostumeAggregate {
    type ID = Uuid;
    type Event = CostumeEvent;
    type Metadata = ();

    fn category() -> &'static str {
        "costume"
    }
}

impl Apply for CostumeAggregate {
    fn apply(&mut self, event: Self::Event, _metadata: Metadata<()>) {
        match event {
            CostumeEvent::CostumeCreated {
                id,
                project_id,
                character_id,
                notes,
                details,
                photos,
                version,
            } => {
                self.id = id;
                self.project_id = project_id;
                self.character_id = character_id;
                self.notes = notes;
                self.details = details;
                self.photos = photos;
                self.version = version;
            }
            CostumeEvent::CostumeNotesUpdated { notes, version, .. } => {
                self.notes = notes;
                self.version = version;
            }
            CostumeEvent::CostumeAssignedToCharacter {
                character_id,
                version,
                ..
            } => {
                self.character_id = Some(character_id);
                self.version = version;
            }
            CostumeEvent::CostumeUnassigned { version, .. } => {
                self.character_id = None;
                self.version = version;
            }
            CostumeEvent::DetailAdded {
                detail, version, ..
            } => {
                self.details.push(detail);
                self.version = version;
            }
            CostumeEvent::DetailRemoved {
                detail_id, version, ..
            } => {
                self.details.retain(|d| d.id != detail_id);
                self.version = version;
            }
            CostumeEvent::PhotoLinked {
                photo_id, version, ..
            } => {
                if !self.photos.contains(&photo_id) {
                    self.photos.push(photo_id);
                }
                self.version = version;
            }
            CostumeEvent::PhotoUnlinked {
                photo_id, version, ..
            } => {
                self.photos.retain(|&id| id != photo_id);
                self.version = version;
            }
        }
    }
}

impl Command<CreateCostume> for CostumeAggregate {
    type Error = CostumeError;
    fn handle(
        &self,
        cmd: CreateCostume,
        _ctx: Context<'_, Self>,
    ) -> Result<Vec<Self::Event>, Self::Error> {
        Ok(vec![CostumeEvent::CostumeCreated {
            id: Uuid::now_v7(),
            project_id: cmd.project_id,
            character_id: None,
            notes: String::new(),
            details: Vec::new(),
            photos: Vec::new(),
            version: AggregateVersion::INITIAL,
        }])
    }
}

impl Command<UpdateCostumeNotes> for CostumeAggregate {
    type Error = CostumeError;
    fn handle(
        &self,
        cmd: UpdateCostumeNotes,
        _ctx: Context<'_, Self>,
    ) -> Result<Vec<Self::Event>, Self::Error> {
        if cmd.version != self.version {
            return Err(CostumeError::ValidationError(
                "Aggregate version mismatch".into(),
            ));
        }
        if cmd.notes == self.notes {
            return Err(CostumeError::ValidationError("Notes unchanged".into()));
        }
        Ok(vec![CostumeEvent::CostumeNotesUpdated {
            id: self.id,
            notes: cmd.notes,
            version: self.version.next(),
        }])
    }
}

impl Command<AssignCostumeToCharacter> for CostumeAggregate {
    type Error = CostumeError;
    fn handle(
        &self,
        cmd: AssignCostumeToCharacter,
        _ctx: Context<'_, Self>,
    ) -> Result<Vec<Self::Event>, Self::Error> {
        if cmd.version != self.version {
            return Err(CostumeError::ValidationError(
                "Aggregate version mismatch".into(),
            ));
        }
        if let Some(assigned_to) = self.character_id {
            if assigned_to != cmd.character_id {
                return Err(CostumeError::AlreadyAssigned { assigned_to });
            }
            return Err(CostumeError::ValidationError(
                "Costume already assigned to this character".into(),
            ));
        }
        Ok(vec![CostumeEvent::CostumeAssignedToCharacter {
            id: self.id,
            character_id: cmd.character_id,
            version: self.version.next(),
        }])
    }
}

impl Command<UnassignCostume> for CostumeAggregate {
    type Error = CostumeError;
    fn handle(
        &self,
        cmd: UnassignCostume,
        _ctx: Context<'_, Self>,
    ) -> Result<Vec<Self::Event>, Self::Error> {
        if cmd.version != self.version {
            return Err(CostumeError::ValidationError(
                "Aggregate version mismatch".into(),
            ));
        }
        if self.character_id.is_none() {
            return Err(CostumeError::ValidationError(
                "Costume is not currently assigned".into(),
            ));
        }
        Ok(vec![CostumeEvent::CostumeUnassigned {
            id: self.id,
            version: self.version.next(),
        }])
    }
}

impl Command<AddDetail> for CostumeAggregate {
    type Error = CostumeError;
    fn handle(
        &self,
        cmd: AddDetail,
        _ctx: Context<'_, Self>,
    ) -> Result<Vec<Self::Event>, Self::Error> {
        if cmd.version != self.version {
            return Err(CostumeError::ValidationError(
                "Aggregate version mismatch".into(),
            ));
        }
        Ok(vec![CostumeEvent::DetailAdded {
            id: self.id,
            detail: cmd.detail,
            version: self.version.next(),
        }])
    }
}

impl Command<RemoveDetail> for CostumeAggregate {
    type Error = CostumeError;
    fn handle(
        &self,
        cmd: RemoveDetail,
        _ctx: Context<'_, Self>,
    ) -> Result<Vec<Self::Event>, Self::Error> {
        if cmd.version != self.version {
            return Err(CostumeError::ValidationError(
                "Aggregate version mismatch".into(),
            ));
        }
        if !self.details.iter().any(|d| d.id == cmd.detail_id) {
            return Err(CostumeError::ValidationError("Detail not found".into()));
        }
        Ok(vec![CostumeEvent::DetailRemoved {
            id: self.id,
            detail_id: cmd.detail_id,
            version: self.version.next(),
        }])
    }
}

impl Command<LinkPhoto> for CostumeAggregate {
    type Error = CostumeError;
    fn handle(
        &self,
        cmd: LinkPhoto,
        _ctx: Context<'_, Self>,
    ) -> Result<Vec<Self::Event>, Self::Error> {
        if cmd.version != self.version {
            return Err(CostumeError::ValidationError(
                "Aggregate version mismatch".into(),
            ));
        }
        if self.photos.contains(&cmd.photo_id) {
            return Err(CostumeError::ValidationError("Photo already linked".into()));
        }
        Ok(vec![CostumeEvent::PhotoLinked {
            id: self.id,
            photo_id: cmd.photo_id,
            version: self.version.next(),
        }])
    }
}

impl Command<UnlinkPhoto> for CostumeAggregate {
    type Error = CostumeError;
    fn handle(
        &self,
        cmd: UnlinkPhoto,
        _ctx: Context<'_, Self>,
    ) -> Result<Vec<Self::Event>, Self::Error> {
        if cmd.version != self.version {
            return Err(CostumeError::ValidationError(
                "Aggregate version mismatch".into(),
            ));
        }
        if !self.photos.contains(&cmd.photo_id) {
            return Err(CostumeError::ValidationError("Photo is not linked".into()));
        }
        Ok(vec![CostumeEvent::PhotoUnlinked {
            id: self.id,
            photo_id: cmd.photo_id,
            version: self.version.next(),
        }])
    }
}

// ── Tests ──────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;
    use crate::testing::make_ctx;

    fn make_costume() -> CostumeAggregate {
        let pid = ProjectId::new();
        let agg = CostumeAggregate::default();
        let events = agg
            .handle(CreateCostume { project_id: pid }, make_ctx())
            .unwrap();
        let mut applied = CostumeAggregate::default();
        for evt in events {
            applied.apply(evt, Default::default());
        }
        applied
    }

    #[test]
    fn test_create_costume_success() {
        let result = CostumeAggregate::default().handle(
            CreateCostume {
                project_id: ProjectId::new(),
            },
            make_ctx(),
        );
        assert!(result.is_ok());
        match result.unwrap().into_iter().next().unwrap() {
            CostumeEvent::CostumeCreated {
                id,
                version,
                character_id,
                ..
            } => {
                assert_ne!(id, Uuid::nil());
                assert_eq!(version, AggregateVersion::INITIAL);
                assert!(character_id.is_none());
            }
            _ => panic!("Expected CostumeCreated"),
        }
    }

    #[test]
    fn test_update_costume_notes_success() {
        let mut agg = make_costume();
        let n: String = "Tear on sleeve".to_string();
        for evt in agg
            .handle(
                UpdateCostumeNotes {
                    id: agg.id,
                    notes: n.clone(),
                    version: agg.version,
                },
                make_ctx(),
            )
            .unwrap()
        {
            agg.apply(evt, Default::default());
        }
        assert_eq!(agg.notes, n);
    }

    #[test]
    fn test_update_costume_notes_idempotency() {
        let agg = make_costume();
        let result = agg.handle(
            UpdateCostumeNotes {
                id: agg.id,
                notes: agg.notes.clone(),
                version: agg.version,
            },
            make_ctx(),
        );
        assert!(result.is_err());
    }

    #[test]
    fn test_update_costume_notes_wrong_version() {
        let agg = make_costume();
        let result = agg.handle(
            UpdateCostumeNotes {
                id: agg.id,
                notes: "X".into(),
                version: AggregateVersion(99),
            },
            make_ctx(),
        );
        assert!(result.is_err());
        assert!(matches!(
            result.unwrap_err(),
            CostumeError::ValidationError(ref m) if m.contains("version mismatch")
        ));
    }

    #[test]
    fn test_assign_costume_success() {
        let mut agg = make_costume();
        let cid = Uuid::now_v7();
        for evt in agg
            .handle(
                AssignCostumeToCharacter {
                    id: agg.id,
                    character_id: cid,
                    version: agg.version,
                },
                make_ctx(),
            )
            .unwrap()
        {
            agg.apply(evt, Default::default());
        }
        assert_eq!(agg.character_id, Some(cid));
    }

    #[test]
    fn test_assign_costume_conflict() {
        let mut agg = make_costume();
        let ca = Uuid::now_v7();
        for evt in agg
            .handle(
                AssignCostumeToCharacter {
                    id: agg.id,
                    character_id: ca,
                    version: agg.version,
                },
                make_ctx(),
            )
            .unwrap()
        {
            agg.apply(evt, Default::default());
        }
        assert_eq!(agg.character_id, Some(ca));
        let result = agg.handle(
            AssignCostumeToCharacter {
                id: agg.id,
                character_id: Uuid::now_v7(),
                version: agg.version,
            },
            make_ctx(),
        );
        assert!(result.is_err());
        assert!(matches!(
            result.unwrap_err(),
            CostumeError::AlreadyAssigned { assigned_to } if assigned_to == ca
        ));
    }

    #[test]
    fn test_unassign_costume_success() {
        let mut agg = make_costume();
        let cid = Uuid::now_v7();
        for evt in agg
            .handle(
                AssignCostumeToCharacter {
                    id: agg.id,
                    character_id: cid,
                    version: agg.version,
                },
                make_ctx(),
            )
            .unwrap()
        {
            agg.apply(evt, Default::default());
        }
        assert_eq!(agg.character_id, Some(cid));
        for evt in agg
            .handle(
                UnassignCostume {
                    id: agg.id,
                    version: agg.version,
                },
                make_ctx(),
            )
            .unwrap()
        {
            agg.apply(evt, Default::default());
        }
        assert_eq!(agg.character_id, None);
    }

    #[test]
    fn test_unassign_not_assigned() {
        let agg = make_costume();
        let result = agg.handle(
            UnassignCostume {
                id: agg.id,
                version: agg.version,
            },
            make_ctx(),
        );
        assert!(result.is_err());
        assert!(matches!(
            result.unwrap_err(),
            CostumeError::ValidationError(ref m) if m.contains("not currently assigned")
        ));
    }

    #[test]
    fn test_add_detail_success() {
        let mut agg = make_costume();
        let did = Uuid::now_v7();
        for evt in agg
            .handle(
                AddDetail {
                    id: agg.id,
                    detail: CostumeDetail {
                        id: did,
                        text: "silk".to_string(),
                    },
                    version: agg.version,
                },
                make_ctx(),
            )
            .unwrap()
        {
            agg.apply(evt, Default::default());
        }
        assert_eq!(agg.details.len(), 1);
        assert_eq!(agg.details[0].text, "silk");
    }

    #[test]
    fn test_remove_detail_success() {
        let mut agg = make_costume();
        let did = Uuid::now_v7();
        for evt in agg
            .handle(
                AddDetail {
                    id: agg.id,
                    detail: CostumeDetail {
                        id: did,
                        text: "x".to_string(),
                    },
                    version: agg.version,
                },
                make_ctx(),
            )
            .unwrap()
        {
            agg.apply(evt, Default::default());
        }
        for evt in agg
            .handle(
                RemoveDetail {
                    id: agg.id,
                    detail_id: did,
                    version: agg.version,
                },
                make_ctx(),
            )
            .unwrap()
        {
            agg.apply(evt, Default::default());
        }
        assert!(agg.details.is_empty());
    }

    #[test]
    fn test_remove_detail_not_found() {
        let agg = make_costume();
        let result = agg.handle(
            RemoveDetail {
                id: agg.id,
                detail_id: Uuid::now_v7(),
                version: agg.version,
            },
            make_ctx(),
        );
        assert!(result.is_err());
        assert!(matches!(
            result.unwrap_err(),
            CostumeError::ValidationError(ref m) if m.contains("not found")
        ));
    }

    #[test]
    fn test_link_photo_success() {
        let mut agg = make_costume();
        let pid = Uuid::now_v7();
        for evt in agg
            .handle(
                LinkPhoto {
                    id: agg.id,
                    photo_id: pid,
                    version: agg.version,
                },
                make_ctx(),
            )
            .unwrap()
        {
            agg.apply(evt, Default::default());
        }
        assert_eq!(agg.photos.len(), 1);
    }

    #[test]
    fn test_link_photo_already_linked() {
        let mut agg = make_costume();
        let pid = Uuid::now_v7();
        for evt in agg
            .handle(
                LinkPhoto {
                    id: agg.id,
                    photo_id: pid,
                    version: agg.version,
                },
                make_ctx(),
            )
            .unwrap()
        {
            agg.apply(evt, Default::default());
        }
        let result = agg.handle(
            LinkPhoto {
                id: agg.id,
                photo_id: pid,
                version: agg.version,
            },
            make_ctx(),
        );
        assert!(result.is_err());
        assert!(matches!(
            result.unwrap_err(),
            CostumeError::ValidationError(ref m) if m.contains("already linked")
        ));
    }

    #[test]
    fn test_unlink_photo_success() {
        let mut agg = make_costume();
        let pid = Uuid::now_v7();
        for evt in agg
            .handle(
                LinkPhoto {
                    id: agg.id,
                    photo_id: pid,
                    version: agg.version,
                },
                make_ctx(),
            )
            .unwrap()
        {
            agg.apply(evt, Default::default());
        }
        for evt in agg
            .handle(
                UnlinkPhoto {
                    id: agg.id,
                    photo_id: pid,
                    version: agg.version,
                },
                make_ctx(),
            )
            .unwrap()
        {
            agg.apply(evt, Default::default());
        }
        assert!(agg.photos.is_empty());
    }

    #[test]
    fn test_unlink_photo_not_linked() {
        let agg = make_costume();
        let result = agg.handle(
            UnlinkPhoto {
                id: agg.id,
                photo_id: Uuid::now_v7(),
                version: agg.version,
            },
            make_ctx(),
        );
        assert!(result.is_err());
        assert!(matches!(
            result.unwrap_err(),
            CostumeError::ValidationError(ref m) if m.contains("not linked")
        ));
    }
} // mod tests
