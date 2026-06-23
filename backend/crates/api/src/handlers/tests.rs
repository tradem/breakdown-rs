// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors

//! Tier-2 mocked-port handler unit tests.

use std::collections::HashMap;
use std::sync::Arc;

use axum::Json;
use axum::extract::State;
use axum::http::StatusCode;
use breakdown_core::calculation::ports::{CalculationCommands, CalculationRepository};
use breakdown_core::calculation::views::CalculationView;
use breakdown_core::character::ports::{CharacterCommands, CharacterRepository};
use breakdown_core::character::views::CharacterView;
use breakdown_core::costume::ports::{CostumeCommands, CostumeRepository};
use breakdown_core::costume::views::CostumeView;
use breakdown_core::error::DomainError;
use breakdown_core::scene::ports::{SceneCommands, SceneRepository};
use breakdown_core::scene::views::SceneView;
use breakdown_core::shared::{AggregateVersion, ProjectId};
use chrono::Utc;
use tokio::sync::Mutex;
use uuid::Uuid;

use crate::handlers::{CreateSceneRequest, create_scene, get_scene};
use crate::state::{AppState, Ports};

#[derive(Clone, Default)]
struct FakeSceneCommands;

impl SceneCommands for FakeSceneCommands {
    async fn create(
        &self,
        cmd: breakdown_core::scene::commands::CreateScene,
    ) -> Result<(Uuid, AggregateVersion), DomainError> {
        Ok((cmd.id, AggregateVersion::INITIAL))
    }
    async fn update_details(
        &self,
        _cmd: breakdown_core::scene::commands::UpdateSceneDetails,
    ) -> Result<AggregateVersion, DomainError> {
        Ok(AggregateVersion::INITIAL.next())
    }
    async fn assign_character(
        &self,
        _cmd: breakdown_core::scene::commands::AssignCharacter,
    ) -> Result<AggregateVersion, DomainError> {
        Ok(AggregateVersion::INITIAL.next())
    }
    async fn remove_character(
        &self,
        _cmd: breakdown_core::scene::commands::RemoveCharacter,
    ) -> Result<AggregateVersion, DomainError> {
        Ok(AggregateVersion::INITIAL.next())
    }
}

#[derive(Clone, Default)]
struct FakeCharacterCommands;

impl CharacterCommands for FakeCharacterCommands {
    async fn create(
        &self,
        cmd: breakdown_core::character::commands::CreateCharacter,
    ) -> Result<(Uuid, AggregateVersion), DomainError> {
        Ok((cmd.id, AggregateVersion::INITIAL))
    }
    async fn update_measurements(
        &self,
        _cmd: breakdown_core::character::commands::UpdateMeasurements,
    ) -> Result<AggregateVersion, DomainError> {
        Ok(AggregateVersion::INITIAL.next())
    }
    async fn update_contact_info(
        &self,
        _cmd: breakdown_core::character::commands::UpdateContactInfo,
    ) -> Result<AggregateVersion, DomainError> {
        Ok(AggregateVersion::INITIAL.next())
    }
}

#[derive(Clone, Default)]
struct FakeCostumeCommands;

impl CostumeCommands for FakeCostumeCommands {
    async fn create(
        &self,
        cmd: breakdown_core::costume::commands::CreateCostume,
    ) -> Result<(Uuid, AggregateVersion), DomainError> {
        Ok((cmd.id, AggregateVersion::INITIAL))
    }
    async fn update_notes(
        &self,
        _cmd: breakdown_core::costume::commands::UpdateCostumeNotes,
    ) -> Result<AggregateVersion, DomainError> {
        Ok(AggregateVersion::INITIAL.next())
    }
    async fn assign_to_character(
        &self,
        _cmd: breakdown_core::costume::commands::AssignCostumeToCharacter,
    ) -> Result<AggregateVersion, DomainError> {
        Ok(AggregateVersion::INITIAL.next())
    }
    async fn unassign(
        &self,
        _cmd: breakdown_core::costume::commands::UnassignCostume,
    ) -> Result<AggregateVersion, DomainError> {
        Ok(AggregateVersion::INITIAL.next())
    }
    async fn add_detail(
        &self,
        _cmd: breakdown_core::costume::commands::AddDetail,
    ) -> Result<AggregateVersion, DomainError> {
        Ok(AggregateVersion::INITIAL.next())
    }
    async fn remove_detail(
        &self,
        _cmd: breakdown_core::costume::commands::RemoveDetail,
    ) -> Result<AggregateVersion, DomainError> {
        Ok(AggregateVersion::INITIAL.next())
    }
    async fn link_photo(
        &self,
        _cmd: breakdown_core::costume::commands::LinkPhoto,
    ) -> Result<AggregateVersion, DomainError> {
        Ok(AggregateVersion::INITIAL.next())
    }
    async fn unlink_photo(
        &self,
        _cmd: breakdown_core::costume::commands::UnlinkPhoto,
    ) -> Result<AggregateVersion, DomainError> {
        Ok(AggregateVersion::INITIAL.next())
    }
}

#[derive(Clone, Default)]
struct FakeCalculationCommands;

impl CalculationCommands for FakeCalculationCommands {
    async fn create(
        &self,
        cmd: breakdown_core::calculation::commands::CreateCalculation,
    ) -> Result<(Uuid, AggregateVersion), DomainError> {
        Ok((cmd.id, AggregateVersion::INITIAL))
    }
    async fn update_header(
        &self,
        _cmd: breakdown_core::calculation::commands::UpdateHeaderInfo,
    ) -> Result<AggregateVersion, DomainError> {
        Ok(AggregateVersion::INITIAL.next())
    }
    async fn add_item(
        &self,
        _cmd: breakdown_core::calculation::commands::AddCalculationItem,
    ) -> Result<AggregateVersion, DomainError> {
        Ok(AggregateVersion::INITIAL.next())
    }
    async fn update_item(
        &self,
        _cmd: breakdown_core::calculation::commands::UpdateCalculationItem,
    ) -> Result<AggregateVersion, DomainError> {
        Ok(AggregateVersion::INITIAL.next())
    }
    async fn remove_item(
        &self,
        _cmd: breakdown_core::calculation::commands::RemoveCalculationItem,
    ) -> Result<AggregateVersion, DomainError> {
        Ok(AggregateVersion::INITIAL.next())
    }
    async fn mark_item_paid(
        &self,
        _cmd: breakdown_core::calculation::commands::MarkItemAsPaid,
    ) -> Result<AggregateVersion, DomainError> {
        Ok(AggregateVersion::INITIAL.next())
    }
    async fn mark_item_unpaid(
        &self,
        _cmd: breakdown_core::calculation::commands::MarkItemAsUnpaid,
    ) -> Result<AggregateVersion, DomainError> {
        Ok(AggregateVersion::INITIAL.next())
    }
}

#[derive(Clone)]
struct FakeSceneRepo {
    scenes: Arc<Mutex<HashMap<Uuid, SceneView>>>,
}

impl Default for FakeSceneRepo {
    fn default() -> Self {
        Self {
            scenes: Arc::new(Mutex::new(HashMap::new())),
        }
    }
}

impl SceneRepository for FakeSceneRepo {
    async fn find_by_id(&self, id: Uuid) -> Result<SceneView, DomainError> {
        self.scenes
            .lock()
            .await
            .get(&id)
            .cloned()
            .ok_or_else(|| DomainError::NotFound(format!("Scene({id})")))
    }
    async fn list_by_project(
        &self,
        _project_id: ProjectId,
        _limit: i64,
        _offset: i64,
    ) -> Result<Vec<SceneView>, DomainError> {
        Ok(Vec::new())
    }
    async fn scenes_by_character(
        &self,
        _character_id: Uuid,
    ) -> Result<Vec<SceneView>, DomainError> {
        Ok(Vec::new())
    }
}

#[derive(Clone, Default)]
struct FakeCharacterRepo;

impl CharacterRepository for FakeCharacterRepo {
    async fn find_by_id(&self, id: Uuid) -> Result<CharacterView, DomainError> {
        Err(DomainError::NotFound(format!("Character({id})")))
    }
    async fn list_by_project(
        &self,
        _project_id: ProjectId,
        _limit: i64,
        _offset: i64,
    ) -> Result<Vec<CharacterView>, DomainError> {
        Ok(Vec::new())
    }
}

#[derive(Clone, Default)]
struct FakeCostumeRepo;

impl CostumeRepository for FakeCostumeRepo {
    async fn find_by_id(&self, id: Uuid) -> Result<CostumeView, DomainError> {
        Err(DomainError::NotFound(format!("Costume({id})")))
    }
    async fn list_by_project(
        &self,
        _project_id: ProjectId,
        _limit: i64,
        _offset: i64,
    ) -> Result<Vec<CostumeView>, DomainError> {
        Ok(Vec::new())
    }
    async fn costumes_by_character(
        &self,
        _character_id: Uuid,
    ) -> Result<Vec<CostumeView>, DomainError> {
        Ok(Vec::new())
    }
    async fn costume_with_details_photos(&self, id: Uuid) -> Result<CostumeView, DomainError> {
        Err(DomainError::NotFound(format!("Costume({id})")))
    }
}

#[derive(Clone, Default)]
struct FakeCalculationRepo;

impl CalculationRepository for FakeCalculationRepo {
    async fn find_by_id(&self, id: Uuid) -> Result<CalculationView, DomainError> {
        Err(DomainError::NotFound(format!("Calculation({id})")))
    }
    async fn list_by_project(
        &self,
        _project_id: ProjectId,
        _limit: i64,
        _offset: i64,
    ) -> Result<Vec<CalculationView>, DomainError> {
        Ok(Vec::new())
    }
    async fn calculation_with_items(&self, id: Uuid) -> Result<CalculationView, DomainError> {
        Err(DomainError::NotFound(format!("Calculation({id})")))
    }
}

#[derive(Clone, Default)]
struct FakePorts {
    scene_commands: FakeSceneCommands,
    scene_repo: FakeSceneRepo,
    character_commands: FakeCharacterCommands,
    character_repo: FakeCharacterRepo,
    costume_commands: FakeCostumeCommands,
    costume_repo: FakeCostumeRepo,
    calculation_commands: FakeCalculationCommands,
    calculation_repo: FakeCalculationRepo,
}

impl Ports for FakePorts {
    type SceneCommands = FakeSceneCommands;
    type SceneRepo = FakeSceneRepo;
    type CharacterCommands = FakeCharacterCommands;
    type CharacterRepo = FakeCharacterRepo;
    type CostumeCommands = FakeCostumeCommands;
    type CostumeRepo = FakeCostumeRepo;
    type CalculationCommands = FakeCalculationCommands;
    type CalculationRepo = FakeCalculationRepo;

    fn scene_commands(&self) -> &Self::SceneCommands {
        &self.scene_commands
    }
    fn scene_repo(&self) -> &Self::SceneRepo {
        &self.scene_repo
    }
    fn character_commands(&self) -> &Self::CharacterCommands {
        &self.character_commands
    }
    fn character_repo(&self) -> &Self::CharacterRepo {
        &self.character_repo
    }
    fn costume_commands(&self) -> &Self::CostumeCommands {
        &self.costume_commands
    }
    fn costume_repo(&self) -> &Self::CostumeRepo {
        &self.costume_repo
    }
    fn calculation_commands(&self) -> &Self::CalculationCommands {
        &self.calculation_commands
    }
    fn calculation_repo(&self) -> &Self::CalculationRepo {
        &self.calculation_repo
    }
}

#[tokio::test]
async fn create_scene_returns_201_with_id_and_version() {
    let state = AppState::new(FakePorts::default());
    let req = CreateSceneRequest {
        project_id: ProjectId::new(),
        details: breakdown_core::scene::events::SceneDetails::default(),
    };

    let result = create_scene(State(state), Json(req)).await;
    let (status, Json(body)) = result.expect("handler should succeed");

    assert_eq!(status, StatusCode::CREATED);
    assert_eq!(body.version, AggregateVersion::INITIAL);
    assert_eq!(body.id.get_version(), Some(uuid::Version::SortRand));
}

#[tokio::test]
async fn get_scene_returns_view_from_repo() {
    let ports = FakePorts::default();
    let scene_id = Uuid::now_v7();
    let view = SceneView {
        id: scene_id,
        project_id: ProjectId::new(),
        scene_number: None,
        location: None,
        mood: None,
        is_schedule_set: false,
        assigned_characters: Vec::new(),
        version: AggregateVersion::INITIAL,
        updated_at: Utc::now(),
    };
    ports
        .scene_repo
        .scenes
        .lock()
        .await
        .insert(scene_id, view.clone());
    let state = AppState::new(ports);

    let result = get_scene(State(state), axum::extract::Path(scene_id)).await;
    let (status, Json(body)) = result.expect("handler should succeed");

    assert_eq!(status, StatusCode::OK);
    assert_eq!(body.id, scene_id);
}

#[tokio::test]
async fn get_scene_returns_404_when_missing() {
    let state = AppState::new(FakePorts::default());

    let result = get_scene(State(state), axum::extract::Path(Uuid::now_v7())).await;
    let (status, Json(body)) = result.expect_err("handler should fail");

    assert_eq!(status, StatusCode::NOT_FOUND);
    assert!(!body.message.is_empty());
}
