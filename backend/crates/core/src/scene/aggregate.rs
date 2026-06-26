// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024 Breakdown RS Contributors

//! Scene aggregate.

use kameo_es::{Apply, Command, Context, Entity, Metadata};
use uuid::Uuid;

use crate::shared::{AggregateVersion, ProjectId};

use super::commands::{AssignCharacter, CreateScene, RemoveCharacter, UpdateSceneDetails};
use super::error::SceneError;
use super::events::SceneEvent;

use crate::scene::events::SceneDetails;

/// State persisted by the Scene aggregate.
#[derive(Debug, Clone, Default)]
pub struct SceneAggregate {
    pub id: Uuid,
    pub project_id: ProjectId,
    pub details: SceneDetails,
    pub assigned_characters: Vec<Uuid>,
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

impl Apply for SceneAggregate {
    fn apply(&mut self, event: Self::Event, _metadata: Metadata<()>) {
        match event {
            SceneEvent::SceneCreated {
                id,
                project_id,
                details,
                assigned_characters,
                version,
            } => {
                self.id = id;
                self.project_id = project_id;
                self.details = details;
                self.assigned_characters = assigned_characters;
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
        }
    }
}

impl Command<CreateScene> for SceneAggregate {
    type Error = SceneError;
    fn handle(
        &self,
        cmd: CreateScene,
        _ctx: Context<'_, Self>,
    ) -> Result<Vec<Self::Event>, Self::Error> {
        Ok(vec![SceneEvent::SceneCreated {
            id: cmd.id,
            project_id: cmd.project_id,
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

// ── Tests ──────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;
    use crate::testing::make_ctx;

    fn create_scene() -> SceneAggregate {
        let pid = ProjectId::new();
        let details = SceneDetails {
            scene_number: Some(1),
            location: Some("Studio A".to_string()),
            mood: Some("IN".to_string()),
            is_schedule_set: false,
        };
        let events = SceneAggregate::default().handle(
            CreateScene {
                id: Uuid::now_v7(),
                project_id: pid,
                details: details.clone(),
            },
            make_ctx(),
        );
        let _ = events;
        let mut applied = SceneAggregate::default();
        for evt in SceneAggregate::default()
            .handle(
                CreateScene {
                    id: Uuid::now_v7(),
                    project_id: pid,
                    details,
                },
                make_ctx(),
            )
            .unwrap()
        {
            applied.apply(evt, Default::default());
        }
        applied
    }

    #[test]
    fn test_create_scene_success() {
        let pid = ProjectId::new();
        let details = SceneDetails {
            scene_number: Some(5),
            location: Some("Berlin".into()),
            mood: Some("DA".into()),
            is_schedule_set: true,
        };
        let result = SceneAggregate::default().handle(
            CreateScene {
                id: Uuid::now_v7(),
                project_id: pid,
                details,
            },
            make_ctx(),
        );
        assert!(result.is_ok());
        let events = result.unwrap();
        assert_eq!(events.len(), 1);
        match events.into_iter().next().unwrap() {
            SceneEvent::SceneCreated {
                id,
                project_id,
                version,
                assigned_characters,
                ..
            } => {
                assert_ne!(id, Uuid::nil());
                assert_eq!(version, AggregateVersion::INITIAL);
                assert!(assigned_characters.is_empty());
                assert_eq!(project_id, pid);
            }
            _ => panic!("Expected SceneCreated"),
        }
    }

    #[test]
    fn test_update_scene_details_success() {
        let mut agg = create_scene();
        let details = SceneDetails {
            scene_number: Some(10),
            location: Some("Exterior".into()),
            mood: Some("AT".into()),
            is_schedule_set: true,
        };
        let event = agg.handle(
            UpdateSceneDetails {
                id: agg.id,
                details: details.clone(),
                version: agg.version,
            },
            make_ctx(),
        );
        for evt in event.unwrap() {
            agg.apply(evt, Default::default());
        }
        assert_eq!(agg.details.scene_number, Some(10));
    }

    #[test]
    fn test_update_scene_details_idempotency() {
        let agg = create_scene();
        let result = agg.handle(
            UpdateSceneDetails {
                id: agg.id,
                details: agg.details.clone(),
                version: agg.version,
            },
            make_ctx(),
        );
        assert!(result.is_err());
        assert!(matches!(
            result.unwrap_err(),
            SceneError::ValidationError(ref m) if m.contains("unchanged")
        ));
    }

    #[test]
    fn test_update_scene_details_wrong_version() {
        let agg = create_scene();
        let result = agg.handle(
            UpdateSceneDetails {
                id: agg.id,
                details: SceneDetails {
                    scene_number: Some(99),
                    ..Default::default()
                },
                version: AggregateVersion(99),
            },
            make_ctx(),
        );
        assert!(result.is_err());
        assert!(matches!(
            result.unwrap_err(),
            SceneError::ValidationError(ref m) if m.contains("version mismatch")
        ));
    }

    #[test]
    fn test_assign_character_success() {
        let mut agg = create_scene();
        let char_id = Uuid::now_v7();
        for evt in agg
            .handle(
                AssignCharacter {
                    id: agg.id,
                    character_id: char_id,
                    version: agg.version,
                },
                make_ctx(),
            )
            .unwrap()
        {
            agg.apply(evt, Default::default());
        }
        assert_eq!(agg.assigned_characters.len(), 1);
        assert_eq!(agg.assigned_characters[0], char_id);
    }

    #[test]
    fn test_assign_character_conflict() {
        let mut agg = create_scene();
        let char_id = Uuid::now_v7();
        for evt in agg
            .handle(
                AssignCharacter {
                    id: agg.id,
                    character_id: char_id,
                    version: agg.version,
                },
                make_ctx(),
            )
            .unwrap()
        {
            agg.apply(evt, Default::default());
        }
        let result = agg.handle(
            AssignCharacter {
                id: agg.id,
                character_id: char_id,
                version: agg.version,
            },
            make_ctx(),
        );
        assert!(result.is_err());
        assert!(matches!(
            result.unwrap_err(),
            SceneError::CharacterAlreadyAssigned
        ));
    }

    #[test]
    fn test_remove_character_success() {
        let mut agg = create_scene();
        let char_id = Uuid::now_v7();
        for evt in agg
            .handle(
                AssignCharacter {
                    id: agg.id,
                    character_id: char_id,
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
                RemoveCharacter {
                    id: agg.id,
                    character_id: char_id,
                    version: agg.version,
                },
                make_ctx(),
            )
            .unwrap()
        {
            agg.apply(evt, Default::default());
        }
        assert!(agg.assigned_characters.is_empty());
    }

    #[test]
    fn test_remove_character_not_assigned() {
        let agg = create_scene();
        let result = agg.handle(
            RemoveCharacter {
                id: agg.id,
                character_id: Uuid::now_v7(),
                version: agg.version,
            },
            make_ctx(),
        );
        assert!(result.is_err());
        assert!(matches!(
            result.unwrap_err(),
            SceneError::ValidationError(ref m) if m.contains("not assigned")
        ));
    }
} // mod tests
