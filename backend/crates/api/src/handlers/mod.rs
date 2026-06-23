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
mod tests;
