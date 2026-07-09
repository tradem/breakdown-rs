// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors

//! Axum-Handler (Request → Command / Query)

use axum::extract::{Path, Query, State};
use axum::http::StatusCode;
use axum::{Json, Router, routing};
use breakdown_core::calculation::commands::{CreateCalculation, UpdateHeaderInfo};
use breakdown_core::calculation::ports::{CalculationCommands, CalculationRepository};
use breakdown_core::calculation::views::CalculationView;
use breakdown_core::character::commands::{CreateCharacter, UpdateMeasurements};
use breakdown_core::character::events::CharacterMeasurements;
use breakdown_core::character::ports::{CharacterCommands, CharacterRepository};
use breakdown_core::character::views::CharacterView;
use breakdown_core::costume::commands::{CreateCostume, UpdateCostumeNotes};
use breakdown_core::costume::ports::{CostumeCommands, CostumeRepository};
use breakdown_core::costume::views::CostumeView;
use breakdown_core::error::DomainError;
use breakdown_core::scene::commands::{CreateScene, UpdateSceneDetails};
use breakdown_core::scene::events::SceneDetails;
use breakdown_core::scene::ports::{SceneCommands, SceneRepository};
use breakdown_core::scene::views::SceneView;
use breakdown_core::shared::{AggregateVersion, ProjectId};
use serde::{Deserialize, Serialize};
use utoipa::{IntoParams, ToSchema};
use uuid::Uuid;

use crate::state::{AppState, Ports, ProductionPorts};

/// JSON error body returned on command/query failures.
#[derive(Debug, Clone, Serialize, ToSchema)]
pub struct ErrorResponse {
    pub message: String,
}

/// Response for aggregate creation endpoints.
#[derive(Debug, Clone, Serialize, ToSchema)]
pub struct IdVersionResponse {
    pub id: Uuid,
    pub version: AggregateVersion,
}

/// Query parameters for paginated list endpoints.
#[derive(Debug, Clone, Deserialize, IntoParams)]
pub struct ListParams {
    pub project_id: ProjectId,
    #[param(default = 50)]
    pub limit: Option<i64>,
    #[param(default = 0)]
    pub offset: Option<i64>,
}

#[derive(Debug, Clone, Deserialize, ToSchema)]
pub struct CreateSceneRequest {
    pub project_id: ProjectId,
    pub details: SceneDetails,
}

#[derive(Debug, Clone, Deserialize, ToSchema)]
pub struct CreateCharacterRequest {
    pub project_id: ProjectId,
    pub name: String,
    pub is_extra: bool,
    pub is_main_character: bool,
}

#[derive(Debug, Clone, Deserialize, ToSchema)]
pub struct CreateCostumeRequest {
    pub project_id: ProjectId,
}

#[derive(Debug, Clone, Deserialize, ToSchema)]
pub struct CreateCalculationRequest {
    pub project_id: ProjectId,
}

#[derive(Debug, Clone, Deserialize, ToSchema)]
pub struct UpdateSceneDetailsRequest {
    pub details: SceneDetails,
    pub version: AggregateVersion,
}

#[derive(Debug, Clone, Deserialize, ToSchema)]
pub struct UpdateMeasurementsRequest {
    pub measurements: CharacterMeasurements,
    pub version: AggregateVersion,
}

#[derive(Debug, Clone, Deserialize, ToSchema)]
pub struct UpdateCostumeNotesRequest {
    pub notes: String,
    pub version: AggregateVersion,
}

#[derive(Debug, Clone, Deserialize, ToSchema)]
pub struct UpdateHeaderInfoRequest {
    pub header: CalculationHeader,
    pub version: AggregateVersion,
}

type ApiResult<T> = Result<(StatusCode, Json<T>), (StatusCode, Json<ErrorResponse>)>;

fn map_err(err: DomainError) -> (StatusCode, Json<ErrorResponse>) {
    let status = match &err {
        DomainError::NotFound(_) => StatusCode::NOT_FOUND,
        DomainError::ValidationError(_) => StatusCode::BAD_REQUEST,
        DomainError::Conflict(_) | DomainError::VersionConflict { .. } => StatusCode::CONFLICT,
    };
    (
        status,
        Json(ErrorResponse {
            message: err.to_string(),
        }),
    )
}

// ---------------------------------------------------------------------------
// Scene handlers
// ---------------------------------------------------------------------------

#[utoipa::path(
    post,
    path = "/scenes",
    request_body = CreateSceneRequest,
    responses(
        (status = 201, description = "Scene created", body = IdVersionResponse),
        (status = 400, description = "Validation error", body = ErrorResponse),
        (status = 409, description = "Conflict", body = ErrorResponse),
    )
)]
pub async fn create_scene<P: Ports>(
    State(state): State<AppState<P>>,
    Json(req): Json<CreateSceneRequest>,
) -> ApiResult<IdVersionResponse> {
    let id = Uuid::now_v7();
    let cmd = CreateScene {
        id,
        project_id: req.project_id,
        details: req.details,
    };
    let (id, version) = state
        .ports
        .scene_commands()
        .create(cmd)
        .await
        .map_err(map_err)?;
    Ok((StatusCode::CREATED, Json(IdVersionResponse { id, version })))
}

#[utoipa::path(
    get,
    path = "/scenes/{id}",
    params(("id" = Uuid, Path, description = "Scene id")),
    responses(
        (status = 200, body = SceneView),
        (status = 404, body = ErrorResponse),
    )
)]
pub async fn get_scene<P: Ports>(
    State(state): State<AppState<P>>,
    Path(id): Path<Uuid>,
) -> ApiResult<SceneView> {
    let view = state
        .ports
        .scene_repo()
        .find_by_id(id)
        .await
        .map_err(map_err)?;
    Ok((StatusCode::OK, Json(view)))
}

#[utoipa::path(
    get,
    path = "/scenes",
    params(ListParams),
    responses((status = 200, body = Vec<SceneView>))
)]
pub async fn list_scenes<P: Ports>(
    State(state): State<AppState<P>>,
    Query(params): Query<ListParams>,
) -> ApiResult<Vec<SceneView>> {
    let views = state
        .ports
        .scene_repo()
        .list_by_project(
            params.project_id,
            params.limit.unwrap_or(50),
            params.offset.unwrap_or(0),
        )
        .await
        .map_err(map_err)?;
    Ok((StatusCode::OK, Json(views)))
}

#[utoipa::path(
    patch,
    path = "/scenes/{id}/details",
    request_body = UpdateSceneDetailsRequest,
    responses(
        (status = 200, body = AggregateVersion),
        (status = 404, body = ErrorResponse),
        (status = 409, body = ErrorResponse),
    )
)]
pub async fn update_scene_details<P: Ports>(
    State(state): State<AppState<P>>,
    Path(id): Path<Uuid>,
    Json(req): Json<UpdateSceneDetailsRequest>,
) -> ApiResult<AggregateVersion> {
    let cmd = UpdateSceneDetails {
        id,
        details: req.details,
        version: req.version,
    };
    let version = state
        .ports
        .scene_commands()
        .update_details(cmd)
        .await
        .map_err(map_err)?;
    Ok((StatusCode::OK, Json(version)))
}

// ---------------------------------------------------------------------------
// Character handlers
// ---------------------------------------------------------------------------

#[utoipa::path(
    post,
    path = "/characters",
    request_body = CreateCharacterRequest,
    responses(
        (status = 201, description = "Character created", body = IdVersionResponse),
        (status = 400, description = "Validation error", body = ErrorResponse),
    )
)]
pub async fn create_character<P: Ports>(
    State(state): State<AppState<P>>,
    Json(req): Json<CreateCharacterRequest>,
) -> ApiResult<IdVersionResponse> {
    let id = Uuid::now_v7();
    let cmd = CreateCharacter {
        id,
        project_id: req.project_id,
        name: req.name,
        is_extra: req.is_extra,
        is_main_character: req.is_main_character,
    };
    let (id, version) = state
        .ports
        .character_commands()
        .create(cmd)
        .await
        .map_err(map_err)?;
    Ok((StatusCode::CREATED, Json(IdVersionResponse { id, version })))
}

#[utoipa::path(
    get,
    path = "/characters/{id}",
    params(("id" = Uuid, Path, description = "Character id")),
    responses((status = 200, body = CharacterView), (status = 404, body = ErrorResponse))
)]
pub async fn get_character<P: Ports>(
    State(state): State<AppState<P>>,
    Path(id): Path<Uuid>,
) -> ApiResult<CharacterView> {
    let view = state
        .ports
        .character_repo()
        .find_by_id(id)
        .await
        .map_err(map_err)?;
    Ok((StatusCode::OK, Json(view)))
}

#[utoipa::path(
    get,
    path = "/characters",
    params(ListParams),
    responses((status = 200, body = Vec<CharacterView>))
)]
pub async fn list_characters<P: Ports>(
    State(state): State<AppState<P>>,
    Query(params): Query<ListParams>,
) -> ApiResult<Vec<CharacterView>> {
    let views = state
        .ports
        .character_repo()
        .list_by_project(
            params.project_id,
            params.limit.unwrap_or(50),
            params.offset.unwrap_or(0),
        )
        .await
        .map_err(map_err)?;
    Ok((StatusCode::OK, Json(views)))
}

#[utoipa::path(
    patch,
    path = "/characters/{id}/measurements",
    request_body = UpdateMeasurementsRequest,
    responses(
        (status = 200, body = AggregateVersion),
        (status = 404, body = ErrorResponse),
        (status = 409, body = ErrorResponse),
    )
)]
pub async fn update_measurements<P: Ports>(
    State(state): State<AppState<P>>,
    Path(id): Path<Uuid>,
    Json(req): Json<UpdateMeasurementsRequest>,
) -> ApiResult<AggregateVersion> {
    let cmd = UpdateMeasurements {
        id,
        measurements: req.measurements,
        version: req.version,
    };
    let version = state
        .ports
        .character_commands()
        .update_measurements(cmd)
        .await
        .map_err(map_err)?;
    Ok((StatusCode::OK, Json(version)))
}

// ---------------------------------------------------------------------------
// Costume handlers
// ---------------------------------------------------------------------------

#[utoipa::path(
    post,
    path = "/costumes",
    request_body = CreateCostumeRequest,
    responses(
        (status = 201, description = "Costume created", body = IdVersionResponse),
        (status = 400, description = "Validation error", body = ErrorResponse),
    )
)]
pub async fn create_costume<P: Ports>(
    State(state): State<AppState<P>>,
    Json(req): Json<CreateCostumeRequest>,
) -> ApiResult<IdVersionResponse> {
    let id = Uuid::now_v7();
    let cmd = CreateCostume {
        id,
        project_id: req.project_id,
    };
    let (id, version) = state
        .ports
        .costume_commands()
        .create(cmd)
        .await
        .map_err(map_err)?;
    Ok((StatusCode::CREATED, Json(IdVersionResponse { id, version })))
}

#[utoipa::path(
    get,
    path = "/costumes/{id}",
    params(("id" = Uuid, Path, description = "Costume id")),
    responses((status = 200, body = CostumeView), (status = 404, body = ErrorResponse))
)]
pub async fn get_costume<P: Ports>(
    State(state): State<AppState<P>>,
    Path(id): Path<Uuid>,
) -> ApiResult<CostumeView> {
    let view = state
        .ports
        .costume_repo()
        .find_by_id(id)
        .await
        .map_err(map_err)?;
    Ok((StatusCode::OK, Json(view)))
}

#[utoipa::path(
    get,
    path = "/costumes",
    params(ListParams),
    responses((status = 200, body = Vec<CostumeView>))
)]
pub async fn list_costumes<P: Ports>(
    State(state): State<AppState<P>>,
    Query(params): Query<ListParams>,
) -> ApiResult<Vec<CostumeView>> {
    let views = state
        .ports
        .costume_repo()
        .list_by_project(
            params.project_id,
            params.limit.unwrap_or(50),
            params.offset.unwrap_or(0),
        )
        .await
        .map_err(map_err)?;
    Ok((StatusCode::OK, Json(views)))
}

#[utoipa::path(
    patch,
    path = "/costumes/{id}/notes",
    request_body = UpdateCostumeNotesRequest,
    responses(
        (status = 200, body = AggregateVersion),
        (status = 404, body = ErrorResponse),
        (status = 409, body = ErrorResponse),
    )
)]
pub async fn update_costume_notes<P: Ports>(
    State(state): State<AppState<P>>,
    Path(id): Path<Uuid>,
    Json(req): Json<UpdateCostumeNotesRequest>,
) -> ApiResult<AggregateVersion> {
    let cmd = UpdateCostumeNotes {
        id,
        notes: req.notes,
        version: req.version,
    };
    let version = state
        .ports
        .costume_commands()
        .update_notes(cmd)
        .await
        .map_err(map_err)?;
    Ok((StatusCode::OK, Json(version)))
}

// ---------------------------------------------------------------------------
// Calculation handlers
// ---------------------------------------------------------------------------

use breakdown_core::calculation::events::CalculationHeader;

#[utoipa::path(
    post,
    path = "/calculations",
    request_body = CreateCalculationRequest,
    responses(
        (status = 201, description = "Calculation created", body = IdVersionResponse),
        (status = 400, description = "Validation error", body = ErrorResponse),
    )
)]
pub async fn create_calculation<P: Ports>(
    State(state): State<AppState<P>>,
    Json(req): Json<CreateCalculationRequest>,
) -> ApiResult<IdVersionResponse> {
    let id = Uuid::now_v7();
    let cmd = CreateCalculation {
        id,
        project_id: req.project_id,
    };
    let (id, version) = state
        .ports
        .calculation_commands()
        .create(cmd)
        .await
        .map_err(map_err)?;
    Ok((StatusCode::CREATED, Json(IdVersionResponse { id, version })))
}

#[utoipa::path(
    get,
    path = "/calculations/{id}",
    params(("id" = Uuid, Path, description = "Calculation id")),
    responses((status = 200, body = CalculationView), (status = 404, body = ErrorResponse))
)]
pub async fn get_calculation<P: Ports>(
    State(state): State<AppState<P>>,
    Path(id): Path<Uuid>,
) -> ApiResult<CalculationView> {
    let view = state
        .ports
        .calculation_repo()
        .find_by_id(id)
        .await
        .map_err(map_err)?;
    Ok((StatusCode::OK, Json(view)))
}

#[utoipa::path(
    get,
    path = "/calculations",
    params(ListParams),
    responses((status = 200, body = Vec<CalculationView>))
)]
pub async fn list_calculations<P: Ports>(
    State(state): State<AppState<P>>,
    Query(params): Query<ListParams>,
) -> ApiResult<Vec<CalculationView>> {
    let views = state
        .ports
        .calculation_repo()
        .list_by_project(
            params.project_id,
            params.limit.unwrap_or(50),
            params.offset.unwrap_or(0),
        )
        .await
        .map_err(map_err)?;
    Ok((StatusCode::OK, Json(views)))
}

#[utoipa::path(
    patch,
    path = "/calculations/{id}/header",
    request_body = UpdateHeaderInfoRequest,
    responses(
        (status = 200, body = AggregateVersion),
        (status = 404, body = ErrorResponse),
        (status = 409, body = ErrorResponse),
    )
)]
pub async fn update_calculation_header<P: Ports>(
    State(state): State<AppState<P>>,
    Path(id): Path<Uuid>,
    Json(req): Json<UpdateHeaderInfoRequest>,
) -> ApiResult<AggregateVersion> {
    let cmd = UpdateHeaderInfo {
        id,
        header: req.header,
        version: req.version,
    };
    let version = state
        .ports
        .calculation_commands()
        .update_header(cmd)
        .await
        .map_err(map_err)?;
    Ok((StatusCode::OK, Json(version)))
}

// ---------------------------------------------------------------------------
// Router
// ---------------------------------------------------------------------------

/// Build the full Axum router using the concrete `ProductionPorts` bundle.
pub fn routes() -> Router<AppState<ProductionPorts>> {
    Router::new()
        .route(
            "/scenes",
            routing::post(create_scene::<ProductionPorts>).get(list_scenes::<ProductionPorts>),
        )
        .route("/scenes/:id", routing::get(get_scene::<ProductionPorts>))
        .route(
            "/scenes/:id/details",
            routing::patch(update_scene_details::<ProductionPorts>),
        )
        .route(
            "/characters",
            routing::post(create_character::<ProductionPorts>)
                .get(list_characters::<ProductionPorts>),
        )
        .route(
            "/characters/:id",
            routing::get(get_character::<ProductionPorts>),
        )
        .route(
            "/characters/:id/measurements",
            routing::patch(update_measurements::<ProductionPorts>),
        )
        .route(
            "/costumes",
            routing::post(create_costume::<ProductionPorts>).get(list_costumes::<ProductionPorts>),
        )
        .route(
            "/costumes/:id",
            routing::get(get_costume::<ProductionPorts>),
        )
        .route(
            "/costumes/:id/notes",
            routing::patch(update_costume_notes::<ProductionPorts>),
        )
        .route(
            "/calculations",
            routing::post(create_calculation::<ProductionPorts>)
                .get(list_calculations::<ProductionPorts>),
        )
        .route(
            "/calculations/:id",
            routing::get(get_calculation::<ProductionPorts>),
        )
        .route(
            "/calculations/:id/header",
            routing::patch(update_calculation_header::<ProductionPorts>),
        )
}

#[cfg(test)]
pub(crate) mod test_helpers {
    use std::collections::HashMap;
    use std::sync::Arc;

    use breakdown_core::calculation::ports::{
        CalculationCommands, CalculationRepository,
    };
    use breakdown_core::calculation::views::CalculationView;
    use breakdown_core::character::ports::{CharacterCommands, CharacterRepository};
    use breakdown_core::character::views::CharacterView;
    use breakdown_core::costume::ports::{CostumeCommands, CostumeRepository};
    use breakdown_core::costume::views::CostumeView;
    use breakdown_core::error::DomainError;
    use breakdown_core::scene::ports::{SceneCommands, SceneRepository};
    use breakdown_core::scene::views::SceneView;
    use breakdown_core::shared::{AggregateVersion, ProjectId};
    use tokio::sync::Mutex;
    use uuid::Uuid;

    use crate::state::Ports;

    #[derive(Clone, Default)]
    pub(crate) struct FakeSceneCommands;

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
    pub(crate) struct FakeCharacterCommands;

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
    pub(crate) struct FakeCostumeCommands;

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
        ) -> Result< AggregateVersion, DomainError> {
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
    pub(crate) struct FakeCalculationCommands;

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
    pub(crate) struct FakeSceneRepo {
        pub(crate) scenes: Arc<Mutex<HashMap<Uuid, SceneView>>>,
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
    pub(crate) struct FakeCharacterRepo;

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
    pub(crate) struct FakeCostumeRepo;

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
        async fn costume_with_details_photos(
            &self,
            id: Uuid,
        ) -> Result<CostumeView, DomainError> {
            Err(DomainError::NotFound(format!("Costume({id})")))
        }
    }

    #[derive(Clone, Default)]
    pub(crate) struct FakeCalculationRepo;

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
        async fn calculation_with_items(
            &self,
            id: Uuid,
        ) -> Result<CalculationView, DomainError> {
            Err(DomainError::NotFound(format!("Calculation({id})")))
        }
    }

    #[derive(Clone, Default)]
    pub(crate) struct FakePorts {
        pub(crate) scene_commands: FakeSceneCommands,
        pub(crate) scene_repo: FakeSceneRepo,
        pub(crate) character_commands: FakeCharacterCommands,
        pub(crate) character_repo: FakeCharacterRepo,
        pub(crate) costume_commands: FakeCostumeCommands,
        pub(crate) costume_repo: FakeCostumeRepo,
        pub(crate) calculation_commands: FakeCalculationCommands,
        pub(crate) calculation_repo: FakeCalculationRepo,
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
}

#[cfg(test)]
mod scene_tests {
    use axum::Json;
    use axum::extract::State;
    use axum::http::StatusCode;
    use breakdown_core::scene::views::SceneView;
    use breakdown_core::shared::{AggregateVersion, ProjectId};
    use chrono::Utc;
    use uuid::Uuid;

    use super::test_helpers::*;
    use crate::handlers::{CreateSceneRequest, create_scene, get_scene};
    use crate::state::AppState;

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
}

#[cfg(test)]
mod character_tests {
    // TODO: Add character handler tests here.
    // Tests from the original tests.rs were only for scene handlers.
    // Character handler tests should be added as new tests.
}

#[cfg(test)]
mod costume_tests {
    // TODO: Add costume handler tests here.
    // Tests from the original tests.rs were only for scene handlers.
    // Costume handler tests should be added as new tests.
}

#[cfg(test)]
mod calculation_tests {
    // TODO: Add calculation handler tests here.
    // Tests from the original tests.rs were only for scene handlers.
    // Calculation handler tests should be added as new tests.
}
