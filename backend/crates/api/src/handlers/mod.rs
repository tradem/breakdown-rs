// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors

//! Axum-Handler (Request → Command / Query)

use axum::extract::{Path, Query, State};
use axum::http::StatusCode;
use axum::{Json, Router, routing};
use breakdown_core::block::commands::{CreateBlock, UpdateBlockTimeSpan};
use breakdown_core::block::ports::{BlockCommands, BlockRepository};
use breakdown_core::block::views::BlockView;
use breakdown_core::character::category::CharacterCategory;
use breakdown_core::character::commands::{CreateCharacter, UpdateContactInfo, UpdateMeasurements};
use breakdown_core::character::events::{CharacterMeasurements, ContactInfo};
use breakdown_core::character::ports::{CharacterCommands, CharacterRepository};
use breakdown_core::character::views::CharacterView;
use breakdown_core::costume::commands::{
    AssignCostumeToCharacter, CreateCostume, UnassignCostume, UpdateCostumeNotes,
};
use breakdown_core::costume::ports::{CostumeCommands, CostumeRepository};
use breakdown_core::costume::views::CostumeView;
use breakdown_core::episode::commands::{CreateEpisode, RenameEpisode};
use breakdown_core::episode::ports::{EpisodeCommands, EpisodeRepository};
use breakdown_core::episode::views::EpisodeView;
use breakdown_core::error::DomainError;
use breakdown_core::scene::commands::{
    AssignCharacter, CreateScene, RemoveCharacter, UpdateSceneDetails,
};
use breakdown_core::scene::events::SceneDetails;
use breakdown_core::scene::ports::{SceneCommands, SceneRepository};
use breakdown_core::scene::views::SceneView;
use breakdown_core::season::commands::{CreateSeason, RenameSeason};
use breakdown_core::season::ports::{SeasonCommands, SeasonRepository};
use breakdown_core::season::views::SeasonView;
use breakdown_core::shared::{AggregateVersion, BlockId, EpisodeId, SeasonId, SeriesId};
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
///
/// `episode_id` scopes Scene lists; `season_id` scopes Character/Block/Episode/Costume lists.
#[derive(Debug, Clone, Deserialize, IntoParams)]
pub struct ListParams {
    #[param(default = 50)]
    pub limit: Option<i64>,
    #[param(default = 0)]
    pub offset: Option<i64>,
    pub episode_id: Option<EpisodeId>,
    pub season_id: Option<SeasonId>,
    pub series_id: Option<SeriesId>,
}

// ---------------------------------------------------------------------------
// Request DTOs
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Deserialize, ToSchema)]
pub struct CreateSceneRequest {
    pub episode_id: EpisodeId,
    pub details: SceneDetails,
}

#[derive(Debug, Clone, Deserialize, ToSchema)]
pub struct CreateCharacterRequest {
    pub season_id: SeasonId,
    pub name: String,
    pub category: CharacterCategory,
}

#[derive(Debug, Clone, Deserialize, ToSchema)]
pub struct CreateCostumeRequest {}

#[derive(Debug, Clone, Deserialize, ToSchema)]
pub struct CreateSeasonRequest {
    pub series_id: SeriesId,
    pub number: i32,
    pub title: Option<String>,
}

#[derive(Debug, Clone, Deserialize, ToSchema)]
pub struct CreateBlockRequest {
    pub season_id: SeasonId,
    pub series_id: SeriesId,
    pub number: i32,
    pub start_date: Option<chrono::NaiveDate>,
    pub end_date: Option<chrono::NaiveDate>,
}

#[derive(Debug, Clone, Deserialize, ToSchema)]
pub struct CreateEpisodeRequest {
    pub block_id: BlockId,
    pub series_id: SeriesId,
    pub number: i32,
    pub name: Option<String>,
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
pub struct UpdateContactInfoRequest {
    pub contact_info: ContactInfo,
    pub version: AggregateVersion,
}

#[derive(Debug, Clone, Deserialize, ToSchema)]
pub struct UpdateCostumeNotesRequest {
    pub notes: String,
    pub version: AggregateVersion,
}

#[derive(Debug, Clone, Deserialize, ToSchema)]
pub struct RenameSeasonRequest {
    pub title: Option<String>,
    pub version: AggregateVersion,
}

#[derive(Debug, Clone, Deserialize, ToSchema)]
pub struct RenameEpisodeRequest {
    pub name: Option<String>,
    pub version: AggregateVersion,
}

#[derive(Debug, Clone, Deserialize, ToSchema)]
pub struct UpdateBlockTimeSpanRequest {
    pub start_date: Option<chrono::NaiveDate>,
    pub end_date: Option<chrono::NaiveDate>,
    pub version: AggregateVersion,
}

#[derive(Debug, Clone, Deserialize, ToSchema)]
pub struct VersionRequest {
    pub version: AggregateVersion,
}

#[derive(Debug, Clone, Deserialize, ToSchema)]
pub struct AssignCharacterRequest {
    pub character_id: Uuid,
    pub version: AggregateVersion,
}

#[derive(Debug, Clone, Deserialize, ToSchema)]
pub struct AssignCostumeRequest {
    pub character_id: Uuid,
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

fn require_episode(params: &ListParams) -> Result<EpisodeId, (StatusCode, Json<ErrorResponse>)> {
    params.episode_id.ok_or_else(|| {
        map_err(DomainError::ValidationError(
            "episode_id is required".into(),
        ))
    })
}

fn require_season(params: &ListParams) -> Result<SeasonId, (StatusCode, Json<ErrorResponse>)> {
    params
        .season_id
        .ok_or_else(|| map_err(DomainError::ValidationError("season_id is required".into())))
}

fn require_series(params: &ListParams) -> Result<SeriesId, (StatusCode, Json<ErrorResponse>)> {
    params
        .series_id
        .ok_or_else(|| map_err(DomainError::ValidationError("series_id is required".into())))
}

// ---------------------------------------------------------------------------
// Season handlers
// ---------------------------------------------------------------------------

#[utoipa::path(
    post,
    path = "/seasons",
    request_body = CreateSeasonRequest,
    responses((status = 201, description = "Season created", body = IdVersionResponse)),
)]
pub async fn create_season<P: Ports>(
    State(state): State<AppState<P>>,
    Json(req): Json<CreateSeasonRequest>,
) -> ApiResult<IdVersionResponse> {
    let id = Uuid::now_v7();
    let cmd = CreateSeason {
        id,
        series_id: req.series_id,
        number: req.number,
        title: req.title,
    };
    let (id, version) = state
        .ports
        .season_commands()
        .create(cmd)
        .await
        .map_err(map_err)?;
    Ok((StatusCode::CREATED, Json(IdVersionResponse { id, version })))
}

#[utoipa::path(
    get,
    path = "/seasons/{id}",
    params(("id" = Uuid, Path, description = "Season id")),
    responses((status = 200, body = SeasonView), (status = 404, body = ErrorResponse)),
)]
pub async fn get_season<P: Ports>(
    State(state): State<AppState<P>>,
    Path(id): Path<Uuid>,
) -> ApiResult<SeasonView> {
    let view = state
        .ports
        .season_repo()
        .find_by_id(id)
        .await
        .map_err(map_err)?;
    Ok((StatusCode::OK, Json(view)))
}

#[utoipa::path(
    patch,
    path = "/seasons/{id}/name",
    request_body = RenameSeasonRequest,
    responses((status = 200, body = AggregateVersion)),
)]
pub async fn rename_season<P: Ports>(
    State(state): State<AppState<P>>,
    Path(id): Path<Uuid>,
    Json(req): Json<RenameSeasonRequest>,
) -> ApiResult<AggregateVersion> {
    let cmd = RenameSeason {
        id,
        title: req.title,
        version: req.version,
    };
    let version = state
        .ports
        .season_commands()
        .rename(cmd)
        .await
        .map_err(map_err)?;
    Ok((StatusCode::OK, Json(version)))
}

// ---------------------------------------------------------------------------
// Block handlers
// ---------------------------------------------------------------------------

#[utoipa::path(
    post,
    path = "/blocks",
    request_body = CreateBlockRequest,
    responses((status = 201, description = "Block created", body = IdVersionResponse)),
)]
pub async fn create_block<P: Ports>(
    State(state): State<AppState<P>>,
    Json(req): Json<CreateBlockRequest>,
) -> ApiResult<IdVersionResponse> {
    let id = Uuid::now_v7();
    let cmd = CreateBlock {
        id,
        season_id: req.season_id,
        series_id: req.series_id,
        number: req.number,
        start_date: req.start_date,
        end_date: req.end_date,
    };
    let (id, version) = state
        .ports
        .block_commands()
        .create(cmd)
        .await
        .map_err(map_err)?;
    Ok((StatusCode::CREATED, Json(IdVersionResponse { id, version })))
}

#[utoipa::path(
    get,
    path = "/blocks/{id}",
    params(("id" = Uuid, Path, description = "Block id")),
    responses((status = 200, body = BlockView), (status = 404, body = ErrorResponse)),
)]
pub async fn get_block<P: Ports>(
    State(state): State<AppState<P>>,
    Path(id): Path<Uuid>,
) -> ApiResult<BlockView> {
    let view = state
        .ports
        .block_repo()
        .find_by_id(id)
        .await
        .map_err(map_err)?;
    Ok((StatusCode::OK, Json(view)))
}

#[utoipa::path(
    get,
    path = "/blocks",
    params(ListParams),
    responses((status = 200, body = Vec<BlockView>)),
)]
pub async fn list_blocks<P: Ports>(
    State(state): State<AppState<P>>,
    Query(params): Query<ListParams>,
) -> ApiResult<Vec<BlockView>> {
    let season_id = require_season(&params)?;
    let views = state
        .ports
        .block_repo()
        .list_by_season(
            season_id,
            params.limit.unwrap_or(50),
            params.offset.unwrap_or(0),
        )
        .await
        .map_err(map_err)?;
    Ok((StatusCode::OK, Json(views)))
}

#[utoipa::path(
    patch,
    path = "/blocks/{id}/time-span",
    request_body = UpdateBlockTimeSpanRequest,
    responses((status = 200, body = AggregateVersion)),
)]
pub async fn update_block_time_span<P: Ports>(
    State(state): State<AppState<P>>,
    Path(id): Path<Uuid>,
    Json(req): Json<UpdateBlockTimeSpanRequest>,
) -> ApiResult<AggregateVersion> {
    let cmd = UpdateBlockTimeSpan {
        id,
        start_date: req.start_date,
        end_date: req.end_date,
        version: req.version,
    };
    let version = state
        .ports
        .block_commands()
        .update_time_span(cmd)
        .await
        .map_err(map_err)?;
    Ok((StatusCode::OK, Json(version)))
}

// ---------------------------------------------------------------------------
// Episode handlers
// ---------------------------------------------------------------------------

#[utoipa::path(
    post,
    path = "/episodes",
    request_body = CreateEpisodeRequest,
    responses((status = 201, description = "Episode created", body = IdVersionResponse)),
)]
pub async fn create_episode<P: Ports>(
    State(state): State<AppState<P>>,
    Json(req): Json<CreateEpisodeRequest>,
) -> ApiResult<IdVersionResponse> {
    let id = Uuid::now_v7();
    let cmd = CreateEpisode {
        id,
        block_id: req.block_id,
        series_id: req.series_id,
        number: req.number,
        name: req.name,
    };
    let (id, version) = state
        .ports
        .episode_commands()
        .create(cmd)
        .await
        .map_err(map_err)?;
    Ok((StatusCode::CREATED, Json(IdVersionResponse { id, version })))
}

#[utoipa::path(
    get,
    path = "/episodes/{id}",
    params(("id" = Uuid, Path, description = "Episode id")),
    responses((status = 200, body = EpisodeView), (status = 404, body = ErrorResponse)),
)]
pub async fn get_episode<P: Ports>(
    State(state): State<AppState<P>>,
    Path(id): Path<Uuid>,
) -> ApiResult<EpisodeView> {
    let view = state
        .ports
        .episode_repo()
        .find_by_id(id)
        .await
        .map_err(map_err)?;
    Ok((StatusCode::OK, Json(view)))
}

#[utoipa::path(
    get,
    path = "/episodes",
    params(ListParams),
    responses((status = 200, body = Vec<EpisodeView>)),
)]
pub async fn list_episodes<P: Ports>(
    State(state): State<AppState<P>>,
    Query(params): Query<ListParams>,
) -> ApiResult<Vec<EpisodeView>> {
    let series_id = require_series(&params)?;
    let views = state
        .ports
        .episode_repo()
        .list_by_series(
            series_id,
            params.limit.unwrap_or(50),
            params.offset.unwrap_or(0),
        )
        .await
        .map_err(map_err)?;
    Ok((StatusCode::OK, Json(views)))
}

#[utoipa::path(
    patch,
    path = "/episodes/{id}/name",
    request_body = RenameEpisodeRequest,
    responses((status = 200, body = AggregateVersion)),
)]
pub async fn rename_episode<P: Ports>(
    State(state): State<AppState<P>>,
    Path(id): Path<Uuid>,
    Json(req): Json<RenameEpisodeRequest>,
) -> ApiResult<AggregateVersion> {
    let cmd = RenameEpisode {
        id,
        name: req.name,
        version: req.version,
    };
    let version = state
        .ports
        .episode_commands()
        .rename(cmd)
        .await
        .map_err(map_err)?;
    Ok((StatusCode::OK, Json(version)))
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
        episode_id: req.episode_id,
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
    let episode_id = require_episode(&params)?;
    let views = state
        .ports
        .scene_repo()
        .list_by_episode(
            episode_id,
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

#[utoipa::path(
    post,
    path = "/scenes/{id}/characters",
    request_body = AssignCharacterRequest,
    responses((status = 200, body = AggregateVersion), (status = 409, body = ErrorResponse)),
)]
pub async fn assign_scene_character<P: Ports>(
    State(state): State<AppState<P>>,
    Path(id): Path<Uuid>,
    Json(req): Json<AssignCharacterRequest>,
) -> ApiResult<AggregateVersion> {
    let cmd = AssignCharacter {
        id,
        character_id: req.character_id,
        version: req.version,
    };
    let version = state
        .ports
        .scene_commands()
        .assign_character(cmd)
        .await
        .map_err(map_err)?;
    Ok((StatusCode::OK, Json(version)))
}

#[utoipa::path(
    delete,
    path = "/scenes/{id}/characters/{character_id}",
    params(("id" = Uuid, Path), ("character_id" = Uuid, Path)),
    responses((status = 200, body = AggregateVersion), (status = 409, body = ErrorResponse)),
)]
pub async fn remove_scene_character<P: Ports>(
    State(state): State<AppState<P>>,
    Path((id, character_id)): Path<(Uuid, Uuid)>,
    Query(version): Query<VersionRequest>,
) -> ApiResult<AggregateVersion> {
    let cmd = RemoveCharacter {
        id,
        character_id,
        version: version.version,
    };
    let version = state
        .ports
        .scene_commands()
        .remove_character(cmd)
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
        season_id: req.season_id,
        name: req.name,
        category: req.category,
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
    let season_id = require_season(&params)?;
    let views = state
        .ports
        .character_repo()
        .list_by_season(
            season_id,
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

#[utoipa::path(
    patch,
    path = "/characters/{id}/contact",
    request_body = UpdateContactInfoRequest,
    responses((status = 200, body = AggregateVersion)),
)]
pub async fn update_contact_info<P: Ports>(
    State(state): State<AppState<P>>,
    Path(id): Path<Uuid>,
    Json(req): Json<UpdateContactInfoRequest>,
) -> ApiResult<AggregateVersion> {
    let cmd = UpdateContactInfo {
        id,
        contact_info: req.contact_info,
        version: req.version,
    };
    let version = state
        .ports
        .character_commands()
        .update_contact_info(cmd)
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
    Json(_req): Json<CreateCostumeRequest>,
) -> ApiResult<IdVersionResponse> {
    let id = Uuid::now_v7();
    let cmd = CreateCostume { id };
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
    let season_id = require_season(&params)?;
    let views = state
        .ports
        .costume_repo()
        .list_by_season(
            season_id,
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

#[utoipa::path(
    post,
    path = "/costumes/{id}/assign",
    request_body = AssignCostumeRequest,
    responses((status = 200, body = AggregateVersion), (status = 409, body = ErrorResponse)),
)]
pub async fn assign_costume<P: Ports>(
    State(state): State<AppState<P>>,
    Path(id): Path<Uuid>,
    Json(req): Json<AssignCostumeRequest>,
) -> ApiResult<AggregateVersion> {
    let cmd = AssignCostumeToCharacter {
        id,
        character_id: req.character_id,
        version: req.version,
    };
    let version = state
        .ports
        .costume_commands()
        .assign_to_character(cmd)
        .await
        .map_err(map_err)?;
    Ok((StatusCode::OK, Json(version)))
}

#[utoipa::path(
    post,
    path = "/costumes/{id}/unassign",
    request_body = UpdateCostumeNotesRequest,
    responses((status = 200, body = AggregateVersion)),
)]
pub async fn unassign_costume<P: Ports>(
    State(state): State<AppState<P>>,
    Path(id): Path<Uuid>,
    Json(req): Json<VersionRequest>,
) -> ApiResult<AggregateVersion> {
    let cmd = UnassignCostume {
        id,
        version: req.version,
    };
    let version = state
        .ports
        .costume_commands()
        .unassign(cmd)
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
        .route("/seasons", routing::post(create_season::<ProductionPorts>))
        .route("/seasons/:id", routing::get(get_season::<ProductionPorts>))
        .route(
            "/seasons/:id/name",
            routing::patch(rename_season::<ProductionPorts>),
        )
        .route(
            "/blocks",
            routing::post(create_block::<ProductionPorts>).get(list_blocks::<ProductionPorts>),
        )
        .route("/blocks/:id", routing::get(get_block::<ProductionPorts>))
        .route(
            "/blocks/:id/time-span",
            routing::patch(update_block_time_span::<ProductionPorts>),
        )
        .route(
            "/episodes",
            routing::post(create_episode::<ProductionPorts>).get(list_episodes::<ProductionPorts>),
        )
        .route(
            "/episodes/:id",
            routing::get(get_episode::<ProductionPorts>),
        )
        .route(
            "/episodes/:id/name",
            routing::patch(rename_episode::<ProductionPorts>),
        )
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
            "/scenes/:id/characters",
            routing::post(assign_scene_character::<ProductionPorts>),
        )
        .route(
            "/scenes/:id/characters/:character_id",
            routing::delete(remove_scene_character::<ProductionPorts>),
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
            "/characters/:id/contact",
            routing::patch(update_contact_info::<ProductionPorts>),
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
            "/costumes/:id/assign",
            routing::post(assign_costume::<ProductionPorts>),
        )
        .route(
            "/costumes/:id/unassign",
            routing::post(unassign_costume::<ProductionPorts>),
        )
}

#[cfg(test)]
pub(crate) mod test_helpers {
    use std::collections::HashMap;
    use std::sync::Arc;

    use breakdown_core::block::commands::{CreateBlock, UpdateBlockTimeSpan};
    use breakdown_core::block::ports::{BlockCommands, BlockRepository};
    use breakdown_core::block::views::BlockView;
    use breakdown_core::character::category::CharacterCategory;
    use breakdown_core::character::commands::{
        CreateCharacter, UpdateContactInfo, UpdateMeasurements,
    };
    use breakdown_core::character::ports::{CharacterCommands, CharacterRepository};
    use breakdown_core::character::views::CharacterView;
    use breakdown_core::costume::commands::{
        AddDetail, AssignCostumeToCharacter, CreateCostume, LinkPhoto, RemoveDetail,
        UnassignCostume, UnlinkPhoto, UpdateCostumeNotes,
    };
    use breakdown_core::costume::ports::{CostumeCommands, CostumeRepository};
    use breakdown_core::costume::views::CostumeView;
    use breakdown_core::episode::commands::{CreateEpisode, RenameEpisode};
    use breakdown_core::episode::ports::{EpisodeCommands, EpisodeRepository};
    use breakdown_core::episode::views::EpisodeView;
    use breakdown_core::error::DomainError;
    use breakdown_core::scene::commands::{
        AssignCharacter, CreateScene, RemoveCharacter, UpdateSceneDetails,
    };
    use breakdown_core::scene::ports::{SceneCommands, SceneRepository};
    use breakdown_core::scene::views::SceneView;
    use breakdown_core::season::commands::{CreateSeason, RenameSeason};
    use breakdown_core::season::ports::{SeasonCommands, SeasonRepository};
    use breakdown_core::season::views::SeasonView;
    use breakdown_core::shared::{AggregateVersion, BlockId, EpisodeId, SeasonId, SeriesId};
    use tokio::sync::Mutex;
    use uuid::Uuid;

    use crate::state::Ports;

    #[derive(Clone, Default)]
    pub(crate) struct FakeSceneCommands;

    impl SceneCommands for FakeSceneCommands {
        async fn create(&self, cmd: CreateScene) -> Result<(Uuid, AggregateVersion), DomainError> {
            Ok((cmd.id, AggregateVersion::INITIAL))
        }
        async fn update_details(
            &self,
            _cmd: UpdateSceneDetails,
        ) -> Result<AggregateVersion, DomainError> {
            Ok(AggregateVersion::INITIAL.next())
        }
        async fn assign_character(
            &self,
            _cmd: AssignCharacter,
        ) -> Result<AggregateVersion, DomainError> {
            Ok(AggregateVersion::INITIAL.next())
        }
        async fn remove_character(
            &self,
            _cmd: RemoveCharacter,
        ) -> Result<AggregateVersion, DomainError> {
            Ok(AggregateVersion::INITIAL.next())
        }
    }

    #[derive(Clone, Default)]
    pub(crate) struct FakeCharacterCommands;

    impl CharacterCommands for FakeCharacterCommands {
        async fn create(
            &self,
            cmd: CreateCharacter,
        ) -> Result<(Uuid, AggregateVersion), DomainError> {
            Ok((cmd.id, AggregateVersion::INITIAL))
        }
        async fn update_measurements(
            &self,
            _cmd: UpdateMeasurements,
        ) -> Result<AggregateVersion, DomainError> {
            Ok(AggregateVersion::INITIAL.next())
        }
        async fn update_contact_info(
            &self,
            _cmd: UpdateContactInfo,
        ) -> Result<AggregateVersion, DomainError> {
            Ok(AggregateVersion::INITIAL.next())
        }
    }

    #[derive(Clone, Default)]
    pub(crate) struct FakeCostumeCommands;

    impl CostumeCommands for FakeCostumeCommands {
        async fn create(
            &self,
            cmd: CreateCostume,
        ) -> Result<(Uuid, AggregateVersion), DomainError> {
            Ok((cmd.id, AggregateVersion::INITIAL))
        }
        async fn update_notes(
            &self,
            _cmd: UpdateCostumeNotes,
        ) -> Result<AggregateVersion, DomainError> {
            Ok(AggregateVersion::INITIAL.next())
        }
        async fn assign_to_character(
            &self,
            _cmd: AssignCostumeToCharacter,
        ) -> Result<AggregateVersion, DomainError> {
            Ok(AggregateVersion::INITIAL.next())
        }
        async fn unassign(&self, _cmd: UnassignCostume) -> Result<AggregateVersion, DomainError> {
            Ok(AggregateVersion::INITIAL.next())
        }
        async fn add_detail(&self, _cmd: AddDetail) -> Result<AggregateVersion, DomainError> {
            Ok(AggregateVersion::INITIAL.next())
        }
        async fn remove_detail(&self, _cmd: RemoveDetail) -> Result<AggregateVersion, DomainError> {
            Ok(AggregateVersion::INITIAL.next())
        }
        async fn link_photo(&self, _cmd: LinkPhoto) -> Result<AggregateVersion, DomainError> {
            Ok(AggregateVersion::INITIAL.next())
        }
        async fn unlink_photo(&self, _cmd: UnlinkPhoto) -> Result<AggregateVersion, DomainError> {
            Ok(AggregateVersion::INITIAL.next())
        }
    }

    #[derive(Clone, Default)]
    pub(crate) struct FakeSeasonCommands;

    impl SeasonCommands for FakeSeasonCommands {
        async fn create(&self, cmd: CreateSeason) -> Result<(Uuid, AggregateVersion), DomainError> {
            Ok((cmd.id, AggregateVersion::INITIAL))
        }
        async fn rename(&self, _cmd: RenameSeason) -> Result<AggregateVersion, DomainError> {
            Ok(AggregateVersion::INITIAL.next())
        }
    }

    #[derive(Clone, Default)]
    pub(crate) struct FakeBlockCommands;

    impl BlockCommands for FakeBlockCommands {
        async fn create(&self, cmd: CreateBlock) -> Result<(Uuid, AggregateVersion), DomainError> {
            Ok((cmd.id, AggregateVersion::INITIAL))
        }
        async fn update_time_span(
            &self,
            _cmd: UpdateBlockTimeSpan,
        ) -> Result<AggregateVersion, DomainError> {
            Ok(AggregateVersion::INITIAL.next())
        }
    }

    #[derive(Clone, Default)]
    pub(crate) struct FakeEpisodeCommands;

    impl EpisodeCommands for FakeEpisodeCommands {
        async fn create(
            &self,
            cmd: CreateEpisode,
        ) -> Result<(Uuid, AggregateVersion), DomainError> {
            Ok((cmd.id, AggregateVersion::INITIAL))
        }
        async fn rename(&self, _cmd: RenameEpisode) -> Result<AggregateVersion, DomainError> {
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
        async fn list_by_episode(
            &self,
            _episode_id: EpisodeId,
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
        async fn list_by_season(
            &self,
            _season_id: SeasonId,
            _limit: i64,
            _offset: i64,
        ) -> Result<Vec<CharacterView>, DomainError> {
            Ok(Vec::new())
        }
        async fn list_by_season_and_category(
            &self,
            _season_id: SeasonId,
            _category: CharacterCategory,
            _limit: i64,
            _offset: i64,
        ) -> Result<Vec<CharacterView>, DomainError> {
            Ok(Vec::new())
        }
        async fn appearances(&self, _character_id: Uuid) -> Result<Vec<EpisodeId>, DomainError> {
            Ok(Vec::new())
        }
    }

    #[derive(Clone, Default)]
    pub(crate) struct FakeCostumeRepo;

    impl CostumeRepository for FakeCostumeRepo {
        async fn find_by_id(&self, id: Uuid) -> Result<CostumeView, DomainError> {
            Err(DomainError::NotFound(format!("Costume({id})")))
        }
        async fn list_by_season(
            &self,
            _season_id: SeasonId,
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
    pub(crate) struct FakeSeasonRepo;

    impl SeasonRepository for FakeSeasonRepo {
        async fn find_by_id(&self, id: Uuid) -> Result<SeasonView, DomainError> {
            Err(DomainError::NotFound(format!("Season({id})")))
        }
        async fn list_by_series(
            &self,
            _series_id: SeriesId,
            _limit: i64,
            _offset: i64,
        ) -> Result<Vec<SeasonView>, DomainError> {
            Ok(Vec::new())
        }
        async fn find_by_series_and_number(
            &self,
            _series_id: SeriesId,
            _number: i32,
        ) -> Result<Option<SeasonView>, DomainError> {
            Ok(None)
        }
    }

    #[derive(Clone, Default)]
    pub(crate) struct FakeBlockRepo;

    impl BlockRepository for FakeBlockRepo {
        async fn find_by_id(&self, id: Uuid) -> Result<BlockView, DomainError> {
            Err(DomainError::NotFound(format!("Block({id})")))
        }
        async fn list_by_season(
            &self,
            _season_id: SeasonId,
            _limit: i64,
            _offset: i64,
        ) -> Result<Vec<BlockView>, DomainError> {
            Ok(Vec::new())
        }
        async fn find_by_series_and_number(
            &self,
            _series_id: SeriesId,
            _number: i32,
        ) -> Result<Option<BlockView>, DomainError> {
            Ok(None)
        }
    }

    #[derive(Clone, Default)]
    pub(crate) struct FakeEpisodeRepo;

    impl EpisodeRepository for FakeEpisodeRepo {
        async fn find_by_id(&self, id: Uuid) -> Result<EpisodeView, DomainError> {
            Err(DomainError::NotFound(format!("Episode({id})")))
        }
        async fn list_by_block(
            &self,
            _block_id: BlockId,
            _limit: i64,
            _offset: i64,
        ) -> Result<Vec<EpisodeView>, DomainError> {
            Ok(Vec::new())
        }
        async fn list_by_series(
            &self,
            _series_id: SeriesId,
            _limit: i64,
            _offset: i64,
        ) -> Result<Vec<EpisodeView>, DomainError> {
            Ok(Vec::new())
        }
        async fn find_by_series_and_number(
            &self,
            _series_id: SeriesId,
            _number: i32,
        ) -> Result<Option<EpisodeView>, DomainError> {
            Ok(None)
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
        pub(crate) season_commands: FakeSeasonCommands,
        pub(crate) season_repo: FakeSeasonRepo,
        pub(crate) block_commands: FakeBlockCommands,
        pub(crate) block_repo: FakeBlockRepo,
        pub(crate) episode_commands: FakeEpisodeCommands,
        pub(crate) episode_repo: FakeEpisodeRepo,
    }

    impl Ports for FakePorts {
        type SceneCommands = FakeSceneCommands;
        type SceneRepo = FakeSceneRepo;
        type CharacterCommands = FakeCharacterCommands;
        type CharacterRepo = FakeCharacterRepo;
        type CostumeCommands = FakeCostumeCommands;
        type CostumeRepo = FakeCostumeRepo;
        type SeasonCommands = FakeSeasonCommands;
        type SeasonRepo = FakeSeasonRepo;
        type BlockCommands = FakeBlockCommands;
        type BlockRepo = FakeBlockRepo;
        type EpisodeCommands = FakeEpisodeCommands;
        type EpisodeRepo = FakeEpisodeRepo;

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
        fn season_commands(&self) -> &Self::SeasonCommands {
            &self.season_commands
        }
        fn season_repo(&self) -> &Self::SeasonRepo {
            &self.season_repo
        }
        fn block_commands(&self) -> &Self::BlockCommands {
            &self.block_commands
        }
        fn block_repo(&self) -> &Self::BlockRepo {
            &self.block_repo
        }
        fn episode_commands(&self) -> &Self::EpisodeCommands {
            &self.episode_commands
        }
        fn episode_repo(&self) -> &Self::EpisodeRepo {
            &self.episode_repo
        }
    }
}

#[cfg(test)]
mod scene_tests {
    use axum::Json;
    use axum::extract::State;
    use axum::http::StatusCode;
    use breakdown_core::scene::events::SceneDetails;
    use breakdown_core::scene::views::SceneView;
    use breakdown_core::shared::{AggregateVersion, EpisodeId};
    use chrono::Utc;
    use uuid::Uuid;

    use super::test_helpers::*;
    use crate::handlers::{CreateSceneRequest, create_scene, get_scene};
    use crate::state::AppState;

    #[tokio::test]
    async fn create_scene_returns_201_with_id_and_version() {
        let state = AppState::new(FakePorts::default());
        let req = CreateSceneRequest {
            episode_id: EpisodeId::new(),
            details: SceneDetails::default(),
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
            episode_id: EpisodeId::new(),
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
    // Character handler unit tests can be added here (mirroring scene_tests).
}

#[cfg(test)]
mod costume_tests {
    // Costume handler unit tests can be added here (mirroring scene_tests).
}
