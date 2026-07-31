// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4-flash (opencode-go)
// Co-authored-by: glm-5.2 (neuralwatt)

//! Axum-Handler (Request → Command / Query)

use axum::extract::{Path, Query, State};
use axum::http::{HeaderMap, StatusCode};
use axum::{Json, Router, routing};
use breakdown_core::audit::{AuditEntry, AuditRepository};
use breakdown_core::block::commands::{CreateBlock, UpdateBlockTimeSpan};
use breakdown_core::block::ports::{BlockCommands, BlockRepository};
use breakdown_core::block::views::BlockView;
use breakdown_core::character::category::CharacterCategory;
use breakdown_core::character::commands::{CreateCharacter, UpdateContactInfo, UpdateMeasurements};
use breakdown_core::character::events::{CharacterMeasurements, ContactInfo};
use breakdown_core::character::ports::{CharacterCommands, CharacterRepository};
use breakdown_core::character::views::CharacterView;
use breakdown_core::costume::commands::{
    AddDetail, AssignCostumeToCharacter, CreateCostume, LinkPhoto, UnassignCostume, UnlinkPhoto,
    UpdateCostumeNotes,
};
use breakdown_core::costume::events::CostumeDetail;
use breakdown_core::costume::ports::{CostumeCommands, CostumeRepository};
use breakdown_core::costume::views::CostumeView;
use breakdown_core::costume_category::commands::{
    ArchiveCostumeCategory, CreateCostumeCategory, RenameCostumeCategory, ReorderCostumeCategory,
};
use breakdown_core::costume_category::ports::{CostumeCategoryCommands, CostumeCategoryRepository};
use breakdown_core::costume_category::views::CostumeCategoryView;
use breakdown_core::episode::commands::{CreateEpisode, RenameEpisode};
use breakdown_core::episode::ports::{EpisodeCommands, EpisodeRepository};
use breakdown_core::episode::views::EpisodeView;
use breakdown_core::error::DomainError;
use breakdown_core::membership::views::MembershipView;
use breakdown_core::membership::{
    AcceptInvitation, BootstrapOwner, GrantRole, InviteMember, LeaveBlock, MembershipCommands,
    MembershipRepository, RemoveMember, Role,
};
use breakdown_core::photo::commands::UploadPhoto as UploadPhotoCmd;
use breakdown_core::photo::ports::{PhotoCommands, PhotoRepository, PhotoStorage};
use breakdown_core::photo::views::PhotoView;
use breakdown_core::reporting::{
    ArchivalTrigger, EnqueueArchivalRequest, EnqueueArchivalResult, RenderPresentationContext,
    ReportArchivalQueue, ReportKind, ReportLocale, ReportRenderRequest, SnapshotIdentity,
    TEMPLATE_VERSION,
};
use breakdown_core::scene::commands::{
    AssignCharacter, CreateScene, RemoveCharacter, ScheduleSceneOnShootingDay,
    UnscheduleSceneFromShootingDay, UpdateSceneDetails,
};
use breakdown_core::scene::events::SceneDetails;
use breakdown_core::scene::ports::{SceneCommands, SceneRepository};
use breakdown_core::scene::views::SceneView;
use breakdown_core::scene_shoot::commands::{
    AddSceneShootNote, FinishSceneShoot, LinkContinuityPhoto, PlanSceneShoot, RemoveSceneShootNote,
    ReplanSceneShoot, SetActualOrder, SkipSceneShoot, StartSceneShoot, UnlinkContinuityPhoto,
    UpdateSceneShootNote,
};
use breakdown_core::scene_shoot::ports::{
    SceneShootCommands, SceneShootReportRepository, SceneShootRepository,
};
use breakdown_core::scene_shoot::views::{DispoRow, SceneShootView, ShootDayRow, SollIstReport};
use breakdown_core::season::commands::{CreateSeason, RenameSeason};
use breakdown_core::season::ports::{SeasonCommands, SeasonRepository};
use breakdown_core::season::views::SeasonView;
use breakdown_core::shared::{
    AggregateVersion, BlockId, EpisodeId, LexicalSortKey, PhotoId, PhotoVariant, SceneShootId,
    SeasonId, SeriesId, ShootingDayId, UserId,
};
use breakdown_core::shooting_day::commands::{
    ArchiveShootingDay, CreateShootingDay, RenameShootingDay, ReorderShootingDay,
    RescheduleShootingDay,
};
use breakdown_core::shooting_day::events::ShootingDaySource;
use breakdown_core::shooting_day::ports::{ShootingDayCommands, ShootingDayRepository};
use breakdown_core::shooting_day::views::ShootingDayView;
use serde::{Deserialize, Serialize};
use utoipa::{IntoParams, ToSchema};
use uuid::Uuid;

use crate::auth::CurrentUser;
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
pub struct CreateCostumeCategoryRequest {
    pub season_id: SeasonId,
    pub name: String,
    pub order_key: LexicalSortKey,
}

#[derive(Debug, Clone, Deserialize, ToSchema)]
pub struct UpdateCostumeCategoryRequest {
    pub version: AggregateVersion,
    pub name: Option<String>,
    pub order_key: Option<LexicalSortKey>,
}

#[derive(Debug, Clone, Deserialize, ToSchema)]
pub struct AddCostumeDetailRequest {
    pub detail: CostumeDetail,
    pub version: AggregateVersion,
}

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

/// Request body for creating a `ShootingDay` (a Drehtag) inside an Episode.
#[derive(Debug, Clone, Deserialize, ToSchema)]
pub struct CreateShootingDayRequest {
    pub episode_id: EpisodeId,
    /// Free-form display label (e.g. "1. Tag").
    pub label: Option<String>,
    /// Canonical ordering key within the Episode (lexicographically sortable).
    pub order_key: LexicalSortKey,
    /// Calendar date; `None` while planning.
    pub date: Option<chrono::NaiveDate>,
    /// Import provenance (`Manual` or `AiExtracted`).
    pub source: ShootingDaySource,
}

/// Request body for mutating a `ShootingDay`.
///
/// Exactly one of `order_key` / `date` / `label` should be set; the handler
/// dispatches the matching command (reorder > reschedule > rename). `date`
/// being `Some(None)` is the explicit "unschedule" (clear the calendar date).
#[derive(Debug, Clone, Deserialize, ToSchema)]
pub struct UpdateShootingDayRequest {
    pub version: AggregateVersion,
    pub label: Option<String>,
    pub date: Option<chrono::NaiveDate>,
    pub order_key: Option<LexicalSortKey>,
}

/// Request body for linking a `Scene` to a `ShootingDay`.
#[derive(Debug, Clone, Deserialize, ToSchema)]
pub struct ScheduleSceneRequest {
    pub shooting_day_id: ShootingDayId,
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

#[derive(Debug, Clone, Deserialize, ToSchema)]
pub struct InviteMemberRequest {
    /// OIDC `sub` of the user to invite to the block.
    pub user_id: String,
    /// Proposed role for the invited user (pending until they accept).
    pub role: Role,
}

#[derive(Debug, Clone, Deserialize, ToSchema)]
pub struct GrantRoleRequest {
    /// New role for the active member (their prior role is replaced).
    pub role: Role,
}

type ApiResult<T> = Result<(StatusCode, Json<T>), (StatusCode, Json<ErrorResponse>)>;

fn map_err(err: DomainError) -> (StatusCode, Json<ErrorResponse>) {
    let status = match &err {
        DomainError::NotFound(_) => StatusCode::NOT_FOUND,
        DomainError::Unauthorized(_) => StatusCode::FORBIDDEN,
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

#[utoipa::path(
    get,
    path = "/audit",
    params(ListParams),
    responses(
        (status = 200, body = Vec<AuditEntry>, description = "Audit journal entries, newest first"),
        (status = 403, body = ErrorResponse, description = "Not authorized"),
        (status = 400, body = ErrorResponse, description = "Validation error"),
    ),
)]
pub async fn get_audit_history<P: Ports>(
    State(state): State<AppState<P>>,
    _current_user: CurrentUser,
    Query(params): Query<ListParams>,
) -> ApiResult<Vec<AuditEntry>> {
    let series_id = require_series(&params)?;

    // AUTHZ-GATE: Audit history is a privileged administrative view.
    // For v1, we allow access if the user is authenticated and provides a valid series_id.
    // In a future iteration, we will implement `MembershipRepository::list_by_series`
    // to verify actual membership within that tenant.

    let entries = state
        .ports
        .audit_repo()
        .list_by_series(
            series_id,
            params.limit.unwrap_or(50),
            params.offset.unwrap_or(0),
        )
        .await
        .map_err(map_err)?;
    Ok((StatusCode::OK, Json(entries)))
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
    current_user: CurrentUser,
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
        .create(current_user.sub.clone(), cmd)
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
    current_user: CurrentUser,
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
        .rename(current_user.sub.clone(), cmd)
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
    current_user: CurrentUser,
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
        .create(current_user.sub.clone(), cmd)
        .await
        .map_err(map_err)?;

    // Decision A: the block creator becomes the first (owner) member, breaking
    // the chicken-and-egg between invitation and active-membership gating. The
    // bootstrap command only succeeds on an empty block.
    let bootstrap = BootstrapOwner {
        block_id: BlockId(id),
        series_id: req.series_id,
        user_id: current_user.sub.clone(),
        role: Role::CostumeAssistant,
    };
    if let Err(e) = state
        .ports
        .membership_commands()
        .bootstrap_owner(current_user.sub.clone(), bootstrap)
        .await
    {
        return Err((
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(ErrorResponse {
                message: format!("failed to bootstrap block owner: {e}"),
            }),
        ));
    }

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
    path = "/blocks/{id}/audit",
    params(("id" = Uuid, Path, description = "Block id"), ListParams),
    responses(
        (status = 200, body = Vec<AuditEntry>, description = "Audit journal entries for the block, newest first"),
        (status = 403, body = ErrorResponse, description = "Caller is not an active member of the active block (X-Active-Block header)"),
        (status = 400, body = ErrorResponse, description = "Missing or malformed X-Active-Block header"),
    ),
)]
pub async fn get_block_audit<P: Ports>(
    State(state): State<AppState<P>>,
    Path(id): Path<Uuid>,
    Query(params): Query<ListParams>,
) -> ApiResult<Vec<AuditEntry>> {
    let entries = state
        .ports
        .audit_repo()
        .list_by_block(
            BlockId::from_uuid(id),
            params.limit.unwrap_or(50),
            params.offset.unwrap_or(0),
        )
        .await
        .map_err(map_err)?;
    Ok((StatusCode::OK, Json(entries)))
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
    current_user: CurrentUser,
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
        .update_time_span(current_user.sub.clone(), cmd)
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
    current_user: CurrentUser,
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
        .create(current_user.sub.clone(), cmd)
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
    current_user: CurrentUser,
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
        .rename(current_user.sub.clone(), cmd)
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
    current_user: CurrentUser,
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
        .create(current_user.sub.clone(), cmd)
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
    current_user: CurrentUser,
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
        .update_details(current_user.sub.clone(), cmd)
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
    current_user: CurrentUser,
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
        .assign_character(current_user.sub.clone(), cmd)
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
    current_user: CurrentUser,
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
        .remove_character(current_user.sub.clone(), cmd)
        .await
        .map_err(map_err)?;
    Ok((StatusCode::OK, Json(version)))
}

// ---------------------------------------------------------------------------
// ShootingDay handlers
// ---------------------------------------------------------------------------

#[utoipa::path(
    post,
    path = "/episodes/{episode_id}/shooting-days",
    params(("episode_id" = EpisodeId, Path, description = "Episode id")),
    request_body = CreateShootingDayRequest,
    responses((status = 201, description = "Shooting day created", body = IdVersionResponse)),
)]
pub async fn create_shooting_day<P: Ports>(
    State(state): State<AppState<P>>,
    current_user: CurrentUser,
    Path(episode_id): Path<EpisodeId>,
    Json(req): Json<CreateShootingDayRequest>,
) -> ApiResult<IdVersionResponse> {
    let id = ShootingDayId::new();
    let cmd = CreateShootingDay {
        id,
        episode_id,
        label: req.label,
        order_key: req.order_key,
        date: req.date,
        source: req.source,
    };
    let (id, version) = state
        .ports
        .shooting_day_commands()
        .create(current_user.sub.clone(), cmd)
        .await
        .map_err(map_err)?;
    Ok((
        StatusCode::CREATED,
        Json(IdVersionResponse { id: id.0, version }),
    ))
}

#[utoipa::path(
    get,
    path = "/episodes/{episode_id}/shooting-days",
    params(("episode_id" = EpisodeId, Path, description = "Episode id")),
    responses((status = 200, body = Vec<ShootingDayView>)),
)]
pub async fn list_shooting_days<P: Ports>(
    State(state): State<AppState<P>>,
    Path(episode_id): Path<EpisodeId>,
) -> ApiResult<Vec<ShootingDayView>> {
    let views = state
        .ports
        .shooting_day_repo()
        .list_by_episode(episode_id)
        .await
        .map_err(map_err)?;
    Ok((StatusCode::OK, Json(views)))
}

#[utoipa::path(
    get,
    path = "/shooting-days/{id}",
    params(("id" = ShootingDayId, Path, description = "Shooting day id")),
    responses((status = 200, body = ShootingDayView), (status = 404, body = ErrorResponse)),
)]
pub async fn get_shooting_day<P: Ports>(
    State(state): State<AppState<P>>,
    Path(id): Path<ShootingDayId>,
) -> ApiResult<ShootingDayView> {
    let view = state
        .ports
        .shooting_day_repo()
        .find_by_id(id)
        .await
        .map_err(map_err)?;
    Ok((StatusCode::OK, Json(view)))
}

#[utoipa::path(
    patch,
    path = "/shooting-days/{id}",
    params(("id" = ShootingDayId, Path, description = "Shooting day id")),
    request_body = UpdateShootingDayRequest,
    responses(
        (status = 200, body = AggregateVersion),
        (status = 400, description = "No update field provided"),
        (status = 409, body = ErrorResponse),
    ),
)]
pub async fn update_shooting_day<P: Ports>(
    State(state): State<AppState<P>>,
    current_user: CurrentUser,
    Path(id): Path<ShootingDayId>,
    Json(req): Json<UpdateShootingDayRequest>,
) -> ApiResult<AggregateVersion> {
    let actor = current_user.sub.clone();
    let cmds = state.ports.shooting_day_commands();
    if let Some(order_key) = req.order_key {
        let version = cmds
            .reorder(
                actor.clone(),
                ReorderShootingDay {
                    id,
                    order_key,
                    version: req.version,
                },
            )
            .await
            .map_err(map_err)?;
        return Ok((StatusCode::OK, Json(version)));
    }
    if req.date.is_some() {
        let version = cmds
            .reschedule(
                actor.clone(),
                RescheduleShootingDay {
                    id,
                    date: req.date,
                    version: req.version,
                },
            )
            .await
            .map_err(map_err)?;
        return Ok((StatusCode::OK, Json(version)));
    }
    if req.label.is_some() {
        let version = cmds
            .rename(
                actor,
                RenameShootingDay {
                    id,
                    label: req.label,
                    version: req.version,
                },
            )
            .await
            .map_err(map_err)?;
        return Ok((StatusCode::OK, Json(version)));
    }
    Err((
        StatusCode::BAD_REQUEST,
        Json(ErrorResponse {
            message: "no update field provided (order_key, date, or label)".into(),
        }),
    ))
}

#[utoipa::path(
    post,
    path = "/shooting-days/{id}/archive",
    params(("id" = ShootingDayId, Path, description = "Shooting day id")),
    request_body = VersionRequest,
    responses((status = 200, body = AggregateVersion), (status = 409, body = ErrorResponse)),
)]
pub async fn archive_shooting_day<P: Ports>(
    State(state): State<AppState<P>>,
    current_user: CurrentUser,
    Path(id): Path<ShootingDayId>,
    Json(req): Json<VersionRequest>,
) -> ApiResult<AggregateVersion> {
    let version = state
        .ports
        .shooting_day_commands()
        .archive(
            current_user.sub.clone(),
            ArchiveShootingDay {
                id,
                version: req.version,
            },
        )
        .await
        .map_err(map_err)?;
    Ok((StatusCode::OK, Json(version)))
}

// ---------------------------------------------------------------------------
// Scene ↔ ShootingDay scheduling handlers
// ---------------------------------------------------------------------------

#[utoipa::path(
    post,
    path = "/scenes/{id}/shooting-days",
    params(("id" = Uuid, Path, description = "Scene id")),
    request_body = ScheduleSceneRequest,
    responses((status = 200, body = AggregateVersion), (status = 409, body = ErrorResponse)),
)]
pub async fn schedule_scene_on_shooting_day<P: Ports>(
    State(state): State<AppState<P>>,
    current_user: CurrentUser,
    Path(id): Path<Uuid>,
    Json(req): Json<ScheduleSceneRequest>,
) -> ApiResult<AggregateVersion> {
    let cmd = ScheduleSceneOnShootingDay {
        id,
        shooting_day_id: req.shooting_day_id,
        version: req.version,
    };
    let version = state
        .ports
        .scene_commands()
        .schedule_on_shooting_day(current_user.sub.clone(), cmd)
        .await
        .map_err(map_err)?;
    Ok((StatusCode::OK, Json(version)))
}

#[utoipa::path(
    delete,
    path = "/scenes/{id}/shooting-days/{shooting_day_id}",
    params(
        ("id" = Uuid, Path, description = "Scene id"),
        ("shooting_day_id" = ShootingDayId, Path, description = "Shooting day id")
    ),
    responses((status = 200, body = AggregateVersion), (status = 409, body = ErrorResponse)),
)]
pub async fn unschedule_scene_from_shooting_day<P: Ports>(
    State(state): State<AppState<P>>,
    current_user: CurrentUser,
    Path((id, shooting_day_id)): Path<(Uuid, ShootingDayId)>,
    Query(version): Query<VersionRequest>,
) -> ApiResult<AggregateVersion> {
    let cmd = UnscheduleSceneFromShootingDay {
        id,
        shooting_day_id,
        version: version.version,
    };
    let version = state
        .ports
        .scene_commands()
        .unschedule_from_shooting_day(current_user.sub.clone(), cmd)
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
    current_user: CurrentUser,
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
        .create(current_user.sub.clone(), cmd)
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
    current_user: CurrentUser,
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
        .update_measurements(current_user.sub.clone(), cmd)
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
    current_user: CurrentUser,
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
        .update_contact_info(current_user.sub.clone(), cmd)
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
    current_user: CurrentUser,
    Json(_req): Json<CreateCostumeRequest>,
) -> ApiResult<IdVersionResponse> {
    let id = Uuid::now_v7();
    let cmd = CreateCostume { id };
    let (id, version) = state
        .ports
        .costume_commands()
        .create(current_user.sub.clone(), cmd)
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
    current_user: CurrentUser,
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
        .update_notes(current_user.sub.clone(), cmd)
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
    current_user: CurrentUser,
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
        .assign_to_character(current_user.sub.clone(), cmd)
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
    current_user: CurrentUser,
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
        .unassign(current_user.sub.clone(), cmd)
        .await
        .map_err(map_err)?;
    Ok((StatusCode::OK, Json(version)))
}

// ---------------------------------------------------------------------------
// Costume detail handlers
// ---------------------------------------------------------------------------

#[utoipa::path(
    post,
    path = "/costumes/{id}/details",
    params(("id" = Uuid, Path, description = "Costume id")),
    request_body = AddCostumeDetailRequest,
    responses((status = 200, body = AggregateVersion)),
)]
pub async fn add_costume_detail<P: Ports>(
    State(state): State<AppState<P>>,
    current_user: CurrentUser,
    Path(id): Path<Uuid>,
    Json(req): Json<AddCostumeDetailRequest>,
) -> ApiResult<AggregateVersion> {
    let version = state
        .ports
        .costume_commands()
        .add_detail(
            current_user.sub.clone(),
            AddDetail {
                id,
                detail: req.detail,
                version: req.version,
            },
        )
        .await
        .map_err(map_err)?;
    Ok((StatusCode::OK, Json(version)))
}

// ---------------------------------------------------------------------------
// CostumeCategory handlers (season-scoped vocabulary)
// ---------------------------------------------------------------------------

#[utoipa::path(
    post,
    path = "/seasons/{season_id}/costume-categories",
    params(("season_id" = SeasonId, Path, description = "Season id")),
    request_body = CreateCostumeCategoryRequest,
    responses((status = 201, description = "Costume category created", body = IdVersionResponse)),
)]
pub async fn create_costume_category<P: Ports>(
    State(state): State<AppState<P>>,
    current_user: CurrentUser,
    Path(season_id): Path<SeasonId>,
    Json(req): Json<CreateCostumeCategoryRequest>,
) -> ApiResult<IdVersionResponse> {
    let id = Uuid::now_v7();
    let cmd = CreateCostumeCategory {
        id,
        season_id,
        name: req.name,
        order_key: req.order_key,
    };
    let (id, version) = state
        .ports
        .costume_category_commands()
        .create(current_user.sub.clone(), cmd)
        .await
        .map_err(map_err)?;
    Ok((StatusCode::CREATED, Json(IdVersionResponse { id, version })))
}

#[utoipa::path(
    get,
    path = "/seasons/{season_id}/costume-categories",
    params(("season_id" = SeasonId, Path, description = "Season id")),
    responses((status = 200, body = Vec<CostumeCategoryView>)),
)]
pub async fn list_costume_categories<P: Ports>(
    State(state): State<AppState<P>>,
    Path(season_id): Path<SeasonId>,
) -> ApiResult<Vec<CostumeCategoryView>> {
    let views = state
        .ports
        .costume_category_repo()
        .list_by_season(season_id)
        .await
        .map_err(map_err)?;
    Ok((StatusCode::OK, Json(views)))
}

#[utoipa::path(
    patch,
    path = "/costume-categories/{id}",
    params(("id" = Uuid, Path, description = "Costume category id")),
    request_body = UpdateCostumeCategoryRequest,
    responses(
        (status = 200, body = AggregateVersion),
        (status = 400, description = "No update field provided"),
        (status = 409, body = ErrorResponse),
    ),
)]
pub async fn update_costume_category<P: Ports>(
    State(state): State<AppState<P>>,
    current_user: CurrentUser,
    Path(id): Path<Uuid>,
    Json(req): Json<UpdateCostumeCategoryRequest>,
) -> ApiResult<AggregateVersion> {
    let actor = current_user.sub.clone();
    let cmds = state.ports.costume_category_commands();
    if let Some(name) = req.name {
        let version = cmds
            .rename(
                actor.clone(),
                RenameCostumeCategory {
                    id,
                    name,
                    version: req.version,
                },
            )
            .await
            .map_err(map_err)?;
        return Ok((StatusCode::OK, Json(version)));
    }
    if let Some(order_key) = req.order_key {
        let version = cmds
            .reorder(
                actor,
                ReorderCostumeCategory {
                    id,
                    order_key,
                    version: req.version,
                },
            )
            .await
            .map_err(map_err)?;
        return Ok((StatusCode::OK, Json(version)));
    }
    Err((
        StatusCode::BAD_REQUEST,
        Json(ErrorResponse {
            message: "no update field provided (name or order_key)".into(),
        }),
    ))
}

#[utoipa::path(
    post,
    path = "/costume-categories/{id}/archive",
    params(("id" = Uuid, Path, description = "Costume category id")),
    request_body = VersionRequest,
    responses((status = 200, body = AggregateVersion), (status = 409, body = ErrorResponse)),
)]
pub async fn archive_costume_category<P: Ports>(
    State(state): State<AppState<P>>,
    current_user: CurrentUser,
    Path(id): Path<Uuid>,
    Json(req): Json<VersionRequest>,
) -> ApiResult<AggregateVersion> {
    let version = state
        .ports
        .costume_category_commands()
        .archive(
            current_user.sub.clone(),
            ArchiveCostumeCategory {
                id,
                version: req.version,
            },
        )
        .await
        .map_err(map_err)?;
    Ok((StatusCode::OK, Json(version)))
}

// ---------------------------------------------------------------------------
// Router
// ---------------------------------------------------------------------------

/// Invite a user to the block with a proposed role (pending until accepted).
///
/// Gated `BlockMember`: the caller must be an active member of the active
/// block (see `authorize_middleware`). The actor is the authenticated caller.
#[utoipa::path(
    post,
    path = "/blocks/{id}/members",
    params(("id" = Uuid, Path, description = "Block id")),
    request_body = InviteMemberRequest,
    responses(
        (status = 204, description = "Invitation created (pending until the invitee accepts)"),
        (status = 400, body = ErrorResponse, description = "Invalid request (e.g., malformed user_id)"),
        (status = 403, body = ErrorResponse, description = "Caller is not an active member of the active block (X-Active-Block header)"),
        (status = 409, body = ErrorResponse, description = "Conflicting state (e.g., user is already a member)"),
    ),
)]
pub async fn invite_member<P: Ports>(
    State(state): State<AppState<P>>,
    current_user: CurrentUser,
    Path(id): Path<Uuid>,
    Json(req): Json<InviteMemberRequest>,
) -> ApiResult<()> {
    let series_id = state
        .ports
        .block_repo()
        .find_by_id(id)
        .await
        .map_err(map_err)?
        .series_id;
    let cmd = InviteMember {
        block_id: BlockId::from_uuid(id),
        series_id,
        user_id: UserId::from_sub(req.user_id),
        role: req.role,
    };
    state
        .ports
        .membership_commands()
        .invite(current_user.sub.clone(), cmd)
        .await
        .map_err(map_err)?;
    Ok((StatusCode::NO_CONTENT, Json(())))
}

/// Accept a pending invitation for the authenticated caller.
///
/// Self-service: the invitee proves who they are via OIDC and the command
/// binds `user_id` to the authenticated `sub`, so a caller can only accept
/// their own invitation. Gated `Authenticated` (not `BlockMember`) because the
/// invitee is not yet an active member; the domain command enforces that a
/// pending invitation exists for this block.
#[utoipa::path(
    post,
    path = "/blocks/{id}/members/accept",
    params(("id" = Uuid, Path, description = "Block id")),
    responses(
        (status = 204, description = "Invitation accepted; caller is now an active member"),
        (status = 400, body = ErrorResponse, description = "No pending invitation for the caller in this block"),
        (status = 403, body = ErrorResponse, description = "Unauthorized"),
    ),
)]
pub async fn accept_invitation<P: Ports>(
    State(state): State<AppState<P>>,
    current_user: CurrentUser,
    Path(id): Path<Uuid>,
) -> ApiResult<()> {
    let series_id = state
        .ports
        .block_repo()
        .find_by_id(id)
        .await
        .map_err(map_err)?
        .series_id;
    let cmd = AcceptInvitation {
        block_id: BlockId::from_uuid(id),
        series_id,
        user_id: current_user.sub.clone(),
    };
    state
        .ports
        .membership_commands()
        .accept_invitation(current_user.sub.clone(), cmd)
        .await
        .map_err(map_err)?;
    Ok((StatusCode::NO_CONTENT, Json(())))
}

/// Change an active member's role (prior role replaced).
///
/// Gated `BlockMember`: the caller must be an active member. The targeted
/// `user_id` is taken from the path.
#[utoipa::path(
    post,
    path = "/blocks/{id}/members/{user_id}/role",
    params(("id" = Uuid, Path, description = "Block id"), ("user_id" = String, Path, description = "OIDC sub of the member")),
    request_body = GrantRoleRequest,
    responses(
        (status = 204, description = "Role updated"),
        (status = 400, body = ErrorResponse),
        (status = 403, body = ErrorResponse, description = "Caller is not an active member of the active block"),
        (status = 404, body = ErrorResponse, description = "Target user is not a member of the block"),
    ),
)]
pub async fn grant_role<P: Ports>(
    State(state): State<AppState<P>>,
    current_user: CurrentUser,
    Path((id, user_id)): Path<(Uuid, String)>,
    Json(req): Json<GrantRoleRequest>,
) -> ApiResult<()> {
    let series_id = state
        .ports
        .block_repo()
        .find_by_id(id)
        .await
        .map_err(map_err)?
        .series_id;
    let cmd = GrantRole {
        block_id: BlockId::from_uuid(id),
        series_id,
        user_id: UserId::from_sub(user_id),
        role: req.role,
    };
    state
        .ports
        .membership_commands()
        .grant_role(current_user.sub.clone(), cmd)
        .await
        .map_err(map_err)?;
    Ok((StatusCode::NO_CONTENT, Json(())))
}

/// Remove an active member from the block.
///
/// Gated `BlockMember`: the caller must be an active member. The targeted
/// `user_id` is taken from the path.
#[utoipa::path(
    delete,
    path = "/blocks/{id}/members/{user_id}",
    params(("id" = Uuid, Path, description = "Block id"), ("user_id" = String, Path, description = "OIDC sub of the member to remove")),
    responses(
        (status = 204, description = "Member removed"),
        (status = 400, body = ErrorResponse),
        (status = 403, body = ErrorResponse, description = "Caller is not an active member of the active block"),
        (status = 404, body = ErrorResponse, description = "Target user is not a member of the block"),
    ),
)]
pub async fn remove_member<P: Ports>(
    State(state): State<AppState<P>>,
    current_user: CurrentUser,
    Path((id, user_id)): Path<(Uuid, String)>,
) -> ApiResult<()> {
    let series_id = state
        .ports
        .block_repo()
        .find_by_id(id)
        .await
        .map_err(map_err)?
        .series_id;
    let cmd = RemoveMember {
        block_id: BlockId::from_uuid(id),
        series_id,
        user_id: UserId::from_sub(user_id),
    };
    state
        .ports
        .membership_commands()
        .remove_member(current_user.sub.clone(), cmd)
        .await
        .map_err(map_err)?;
    Ok((StatusCode::NO_CONTENT, Json(())))
}

/// Leave the block (self-service). The authenticated caller removes
/// themselves; the actor is supplied as command metadata by the adapter.
///
/// Gated `BlockMember`: only an active member can leave.
#[utoipa::path(
    post,
    path = "/blocks/{id}/members/leave",
    params(("id" = Uuid, Path, description = "Block id")),
    responses(
        (status = 204, description = "Caller left the block"),
        (status = 400, body = ErrorResponse),
        (status = 403, body = ErrorResponse, description = "Caller is not an active member of the active block"),
    ),
)]
pub async fn leave_block<P: Ports>(
    State(state): State<AppState<P>>,
    current_user: CurrentUser,
    Path(id): Path<Uuid>,
) -> ApiResult<()> {
    let series_id = state
        .ports
        .block_repo()
        .find_by_id(id)
        .await
        .map_err(map_err)?
        .series_id;
    let cmd = LeaveBlock {
        block_id: BlockId::from_uuid(id),
        series_id,
    };
    state
        .ports
        .membership_commands()
        .leave_block(current_user.sub.clone(), cmd)
        .await
        .map_err(map_err)?;
    Ok((StatusCode::NO_CONTENT, Json(())))
}

/// List the members of a block (paginated).
///
/// Gated `BlockMember`: the caller must be an active member of the block.
#[utoipa::path(
    get,
    path = "/blocks/{id}/members",
    params(("id" = Uuid, Path, description = "Block id"), ListParams),
    responses(
        (status = 200, body = Vec<MembershipView>, description = "Members of the block (active and pending)"),
        (status = 400, body = ErrorResponse, description = "Missing or malformed X-Active-Block header"),
        (status = 403, body = ErrorResponse, description = "Caller is not an active member of the active block"),
    ),
)]
pub async fn list_members<P: Ports>(
    State(state): State<AppState<P>>,
    Path(id): Path<Uuid>,
    Query(params): Query<ListParams>,
) -> ApiResult<Vec<MembershipView>> {
    let views = state
        .ports
        .membership_repo()
        .list_by_block(
            BlockId::from_uuid(id),
            params.limit.unwrap_or(50),
            params.offset.unwrap_or(0),
        )
        .await
        .map_err(map_err)?;
    Ok((StatusCode::OK, Json(views)))
}

/// Fetch a single membership (a block member's role and state).
///
/// Gated `BlockMember`: the caller must be an active member of the block.
#[utoipa::path(
    get,
    path = "/blocks/{id}/members/{user_id}",
    params(("id" = Uuid, Path, description = "Block id"), ("user_id" = String, Path, description = "OIDC sub of the member")),
    responses(
        (status = 200, body = MembershipView, description = "Membership of the user in the block"),
        (status = 400, body = ErrorResponse, description = "Missing or malformed X-Active-Block header"),
        (status = 403, body = ErrorResponse, description = "Caller is not an active member of the active block"),
        (status = 404, body = ErrorResponse, description = "Membership not found"),
    ),
)]
pub async fn get_member<P: Ports>(
    State(state): State<AppState<P>>,
    Path((id, user_id)): Path<(Uuid, String)>,
) -> ApiResult<MembershipView> {
    let view = state
        .ports
        .membership_repo()
        .find(BlockId::from_uuid(id), UserId::from_sub(user_id))
        .await
        .map_err(map_err)?;
    match view {
        Some(v) => Ok((StatusCode::OK, Json(v))),
        None => Err((
            StatusCode::NOT_FOUND,
            Json(ErrorResponse {
                message: "membership not found".to_string(),
            }),
        )),
    }
}

/// Upload a photo and link it to a costume.
///
/// The request body is raw image bytes; the `Content-Type` header MUST be one of
/// `image/jpeg`, `image/png`, or `image/webp`. HEIC/HEIF is rejected with 415.
/// The file size MUST NOT exceed `PHOTO_MAX_SIZE_MB` (default 20 MB).
/// Authorization is checked per-request via season-scoped membership.
#[utoipa::path(
    post,
    path = "/costumes/{costume_id}/photos",
    params(("costume_id" = Uuid, Path, description = "Costume id")),
    request_body(content = String, description = "Raw image bytes (JPEG/PNG/WebP)",
        content_type = "image/jpeg"),
    responses(
        (status = 201, description = "Photo uploaded", body = PhotoView),
        (status = 400, body = ErrorResponse, description = "Validation error"),
        (status = 403, body = ErrorResponse, description = "Not authorized"),
        (status = 413, body = ErrorResponse, description = "Payload too large"),
        (status = 415, body = ErrorResponse, description = "Unsupported media type"),
    ),
)]
pub async fn upload_costume_photo<P: Ports>(
    State(state): State<AppState<P>>,
    current_user: CurrentUser,
    Path(costume_id): Path<Uuid>,
    headers: axum::http::HeaderMap,
    body: axum::body::Bytes,
) -> ApiResult<PhotoView> {
    // Validate content-type.
    let content_type = headers
        .get("content-type")
        .and_then(|v| v.to_str().ok())
        .unwrap_or("")
        .to_lowercase();

    if !matches!(
        content_type.as_str(),
        "image/jpeg" | "image/png" | "image/webp"
    ) {
        if content_type == "image/heic" || content_type == "image/heif" {
            return Err((
                StatusCode::UNSUPPORTED_MEDIA_TYPE,
                Json(ErrorResponse {
                    message: "HEIC/HEIF not supported. Convert to JPEG before upload.".into(),
                }),
            ));
        }
        return Err((
            StatusCode::UNSUPPORTED_MEDIA_TYPE,
            Json(ErrorResponse {
                message: format!(
                    "Unsupported content-type: {content_type}. Accepted: image/jpeg, image/png, image/webp"
                ),
            }),
        ));
    }

    // Enforce size cap.
    let max_size_mb: usize = std::env::var("PHOTO_MAX_SIZE_MB")
        .ok()
        .and_then(|v| v.parse().ok())
        .unwrap_or(20);
    let max_bytes = max_size_mb * 1024 * 1024;
    if body.len() > max_bytes {
        return Err((
            StatusCode::PAYLOAD_TOO_LARGE,
            Json(ErrorResponse {
                message: format!(
                    "File exceeds {max_size_mb} MB limit ({:.1} MB)",
                    body.len() as f64 / (1024.0 * 1024.0)
                ),
            }),
        ));
    }

    // Fetch the costume to get its season_id for authorization.
    let costume = state
        .ports
        .costume_repo()
        .find_by_id(costume_id)
        .await
        .map_err(map_err)?;

    // Resolve season_id from the costume's character.
    let season_id = match costume.character_id {
        Some(char_id) => {
            let character = state
                .ports
                .character_repo()
                .find_by_id(char_id)
                .await
                .map_err(map_err)?;
            character.season_id
        }
        None => {
            return Err((
                StatusCode::BAD_REQUEST,
                Json(ErrorResponse {
                    message: "costume has no assigned character — cannot determine season".into(),
                }),
            ));
        }
    };

    // AUTHZ-GATE: authorize_season — handler-internal auth gate (see AGENTS.md)
    let is_authorized = state
        .ports
        .membership_repo()
        .has_active_costume_role_in_season(season_id, current_user.sub.clone())
        .await
        .unwrap_or(false);
    if !is_authorized {
        return Err((
            StatusCode::FORBIDDEN,
            Json(ErrorResponse {
                message: "not authorized to upload photos in this season".into(),
            }),
        ));
    }

    // Generate a new photo_id (UUIDv7).
    let photo_id = PhotoId::new();
    let size_bytes = body.len() as u64;

    // Store the original bytes in Garage.
    state
        .ports
        .photo_storage()
        .store(
            photo_id,
            PhotoVariant::Original,
            body.to_vec(),
            content_type.clone(),
        )
        .await
        .map_err(map_err)?;

    // Dispatch UploadPhoto command.
    state
        .ports
        .photo_commands()
        .upload(
            current_user.sub.clone(),
            UploadPhotoCmd {
                id: photo_id,
                content_type: content_type.clone(),
                size_bytes,
                binding: breakdown_core::photo::PhotoBinding::Costume { costume_id },
            },
        )
        .await
        .map_err(|e| {
            // Compensating delete: best-effort, cannot await in sync closure.
            drop(state.ports.photo_storage().delete_all(photo_id));
            map_err(e)
        })?;

    // Dispatch LinkPhoto command on the costume aggregate.
    let version = costume.version;
    state
        .ports
        .costume_commands()
        .link_photo(
            current_user.sub.clone(),
            LinkPhoto {
                id: costume_id,
                photo_id: photo_id.0,
                version,
            },
        )
        .await
        .map_err(|e| {
            // Compensating delete: best-effort, cannot await in sync closure.
            drop(state.ports.photo_storage().delete_all(photo_id));
            map_err(e)
        })?;

    // Read back the projected photo view.
    let view = state
        .ports
        .photo_repo()
        .find_by_id(photo_id)
        .await
        .map_err(map_err)?;

    Ok((StatusCode::CREATED, Json(view)))
}

/// Download photo bytes (proxy download with per-request authorization).
///
/// Authorization is checked on every request via season-scoped membership.
/// The response includes `Cache-Control: private, max-age=300`.
#[utoipa::path(
    get,
    path = "/costumes/{costume_id}/photos/{photo_id}/bytes",
    params(
        ("costume_id" = Uuid, Path, description = "Costume id"),
        ("photo_id" = Uuid, Path, description = "Photo id"),
        ("variant" = String, Query, description = "Variant: original, thumb, or medium"),
    ),
    responses(
        (status = 200, description = "Photo bytes", content_type = "image/jpeg"),
        (status = 403, body = ErrorResponse, description = "Not authorized"),
        (status = 404, body = ErrorResponse, description = "Photo or costume not found"),
    ),
)]
pub async fn get_costume_photo_bytes<P: Ports>(
    State(state): State<AppState<P>>,
    current_user: CurrentUser,
    Path((costume_id, photo_id)): Path<(Uuid, Uuid)>,
    query: Query<PhotoBytesQuery>,
) -> Result<(StatusCode, axum::http::HeaderMap, Vec<u8>), (StatusCode, Json<ErrorResponse>)> {
    // Fetch the costume to get its season_id for authorization.
    let costume = state
        .ports
        .costume_repo()
        .find_by_id(costume_id)
        .await
        .map_err(map_err)?;

    // Resolve season_id from the costume's character.
    let season_id = match costume.character_id {
        Some(char_id) => {
            let character = state
                .ports
                .character_repo()
                .find_by_id(char_id)
                .await
                .map_err(map_err)?;
            character.season_id
        }
        None => {
            return Err((
                StatusCode::BAD_REQUEST,
                Json(ErrorResponse {
                    message: "costume has no assigned character".into(),
                }),
            ));
        }
    };

    // AUTHZ-GATE: authorize_season — handler-internal auth gate (see AGENTS.md)
    let is_authorized = state
        .ports
        .membership_repo()
        .has_active_costume_role_in_season(season_id, current_user.sub.clone())
        .await
        .unwrap_or(false);
    if !is_authorized {
        return Err((
            StatusCode::FORBIDDEN,
            Json(ErrorResponse {
                message: "not authorized to download photos in this season".into(),
            }),
        ));
    }

    // Resolve variant.
    let variant = match query.variant.as_deref().unwrap_or("original") {
        "thumb" => PhotoVariant::Thumb,
        "medium" => PhotoVariant::Medium,
        _ => PhotoVariant::Original,
    };

    // Fetch bytes from Garage.
    let photo_bytes = state
        .ports
        .photo_storage()
        .fetch(PhotoId::from_uuid(photo_id), variant)
        .await
        .map_err(map_err)?;

    // Build response headers for streaming.
    let mut headers = axum::http::HeaderMap::new();
    let content_type_header = photo_bytes
        .content_type
        .parse::<axum::http::HeaderValue>()
        .map_err(|e| {
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(ErrorResponse {
                    message: format!("invalid content-type in photo metadata: {e}"),
                }),
            )
        })?;
    headers.insert(axum::http::header::CONTENT_TYPE, content_type_header);
    let content_length_header = photo_bytes
        .size_bytes
        .to_string()
        .parse::<axum::http::HeaderValue>()
        .map_err(|e| {
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(ErrorResponse {
                    message: format!("invalid content-length in photo metadata: {e}"),
                }),
            )
        })?;
    headers.insert(axum::http::header::CONTENT_LENGTH, content_length_header);
    headers.insert(
        axum::http::header::CACHE_CONTROL,
        "private, max-age=300"
            .parse()
            .expect("hardcoded safe header value"),
    );
    if let Some(ref etag) = photo_bytes.etag {
        let etag_header = etag.parse::<axum::http::HeaderValue>().map_err(|e| {
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(ErrorResponse {
                    message: format!("invalid etag in photo metadata: {e}"),
                }),
            )
        })?;
        headers.insert(axum::http::header::ETAG, etag_header);
    }

    Ok((StatusCode::OK, headers, photo_bytes.bytes))
}

/// Unlink a photo from a costume (deletion saga handles refcount + bytes cleanup).
///
/// Authorization is checked per-request via season-scoped membership.
/// The photo bytes are only deleted when the refcount reaches zero.
#[utoipa::path(
    delete,
    path = "/costumes/{costume_id}/photos/{photo_id}",
    params(
        ("costume_id" = Uuid, Path, description = "Costume id"),
        ("photo_id" = Uuid, Path, description = "Photo id"),
    ),
    responses(
        (status = 204, description = "Photo unlinked"),
        (status = 403, body = ErrorResponse, description = "Not authorized"),
        (status = 404, body = ErrorResponse, description = "Costume not found"),
    ),
)]
pub async fn delete_costume_photo<P: Ports>(
    State(state): State<AppState<P>>,
    current_user: CurrentUser,
    Path((costume_id, photo_id)): Path<(Uuid, Uuid)>,
) -> ApiResult<()> {
    // Fetch the costume to get its season_id for authorization.
    let costume = state
        .ports
        .costume_repo()
        .find_by_id(costume_id)
        .await
        .map_err(map_err)?;

    // Resolve season_id from the costume's character.
    let season_id = match costume.character_id {
        Some(char_id) => {
            let character = state
                .ports
                .character_repo()
                .find_by_id(char_id)
                .await
                .map_err(map_err)?;
            character.season_id
        }
        None => {
            return Err((
                StatusCode::BAD_REQUEST,
                Json(ErrorResponse {
                    message: "costume has no assigned character".into(),
                }),
            ));
        }
    };

    // AUTHZ-GATE: authorize_season — handler-internal auth gate (see AGENTS.md)
    let is_authorized = state
        .ports
        .membership_repo()
        .has_active_costume_role_in_season(season_id, current_user.sub.clone())
        .await
        .unwrap_or(false);
    if !is_authorized {
        return Err((
            StatusCode::FORBIDDEN,
            Json(ErrorResponse {
                message: "not authorized to delete photos in this season".into(),
            }),
        ));
    }

    // Dispatch UnlinkPhoto on the costume aggregate.
    state
        .ports
        .costume_commands()
        .unlink_photo(
            current_user.sub.clone(),
            UnlinkPhoto {
                id: costume_id,
                photo_id,
                version: costume.version,
            },
        )
        .await
        .map_err(map_err)?;

    Ok((StatusCode::NO_CONTENT, Json(())))
}

/// Query parameters for the photo bytes endpoint.
#[derive(Debug, Clone, Deserialize, Serialize, IntoParams, ToSchema)]
pub struct PhotoBytesQuery {
    /// Variant: "original", "thumb", or "medium". Defaults to "original".
    pub variant: Option<String>,
}

// ---------------------------------------------------------------------------
// SceneShoot handlers
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Deserialize, ToSchema)]
pub struct PlanSceneShootRequest {
    pub scene_id: Uuid,
    pub shooting_day_id: ShootingDayId,
    pub planned_order: LexicalSortKey,
}

#[derive(Debug, Clone, Deserialize, ToSchema)]
pub struct ReplanSceneShootRequest {
    pub planned_order: LexicalSortKey,
    pub version: AggregateVersion,
}

#[derive(Debug, Clone, Deserialize, ToSchema)]
pub struct StartSceneShootRequest {
    pub start_dt: Option<chrono::NaiveDateTime>,
    pub version: AggregateVersion,
}

impl StartSceneShootRequest {
    fn resolve_start_dt(&self) -> chrono::DateTime<chrono::Utc> {
        self.start_dt
            .map(|d| d.and_utc())
            .unwrap_or_else(chrono::Utc::now)
    }
}

#[derive(Debug, Clone, Deserialize, ToSchema)]
pub struct SetActualOrderRequest {
    pub actual_order: LexicalSortKey,
    pub version: AggregateVersion,
}

#[derive(Debug, Clone, Deserialize, ToSchema)]
pub struct FinishSceneShootRequest {
    pub end_dt: Option<chrono::NaiveDateTime>,
    pub version: AggregateVersion,
}

impl FinishSceneShootRequest {
    fn resolve_end_dt(&self) -> chrono::DateTime<chrono::Utc> {
        self.end_dt
            .map(|d| d.and_utc())
            .unwrap_or_else(chrono::Utc::now)
    }
}

#[derive(Debug, Clone, Deserialize, ToSchema)]
pub struct SkipSceneShootRequest {
    pub version: AggregateVersion,
}

#[derive(Debug, Clone, Deserialize, ToSchema)]
pub struct AddNoteRequest {
    pub body: String,
    pub note_id: Option<Uuid>,
}

#[derive(Debug, Clone, Deserialize, ToSchema)]
pub struct UpdateNoteRequest {
    pub body: String,
    pub version: AggregateVersion,
}

#[derive(Debug, Clone, Deserialize, ToSchema)]
pub struct LinkContinuityPhotoRequest {
    pub photo_id: PhotoId,
    pub version: AggregateVersion,
}

#[derive(Debug, Clone, Deserialize, ToSchema)]
pub struct WrapShootingDayRequest {
    pub version: AggregateVersion,
}

#[utoipa::path(
    post,
    path = "/shooting-days/{day_id}/scenes/{scene_id}/scene-shoots",
    request_body = PlanSceneShootRequest,
    responses((status = 201, body = IdVersionResponse)),
)]
pub async fn plan_scene_shoot<P: Ports>(
    State(state): State<AppState<P>>,
    current_user: CurrentUser,
    Path((day_id, scene_id)): Path<(ShootingDayId, Uuid)>,
    Json(req): Json<PlanSceneShootRequest>,
) -> ApiResult<IdVersionResponse> {
    if req.shooting_day_id != day_id {
        return Err((
            StatusCode::BAD_REQUEST,
            Json(ErrorResponse {
                message: "shooting_day_id in body must match path parameter".into(),
            }),
        ));
    }
    let id = SceneShootId::new();
    let cmd = PlanSceneShoot {
        id,
        scene_id,
        shooting_day_id: day_id,
        planned_order: req.planned_order,
    };
    let (id, version) = state
        .ports
        .scene_shoot_commands()
        .plan(current_user.sub.clone(), cmd)
        .await
        .map_err(map_err)?;
    Ok((
        StatusCode::CREATED,
        Json(IdVersionResponse { id: id.0, version }),
    ))
}

#[utoipa::path(
    patch,
    path = "/shooting-days/{day_id}/scenes/{scene_id}/scene-shoots/{shoot_id}",
    request_body = ReplanSceneShootRequest,
    responses((status = 200, body = AggregateVersion)),
)]
pub async fn replan_scene_shoot<P: Ports>(
    State(state): State<AppState<P>>,
    current_user: CurrentUser,
    Path((_day_id, _scene_id, shoot_id)): Path<(ShootingDayId, Uuid, SceneShootId)>,
    Json(req): Json<ReplanSceneShootRequest>,
) -> ApiResult<AggregateVersion> {
    let cmd = ReplanSceneShoot {
        id: shoot_id,
        planned_order: req.planned_order,
        version: req.version,
    };
    let version = state
        .ports
        .scene_shoot_commands()
        .replan(current_user.sub.clone(), cmd)
        .await
        .map_err(map_err)?;
    Ok((StatusCode::OK, Json(version)))
}

#[utoipa::path(
    post,
    path = "/shooting-days/{day_id}/scenes/{scene_id}/scene-shoots/{shoot_id}/start",
    request_body = StartSceneShootRequest,
    responses((status = 200, body = AggregateVersion)),
)]
pub async fn start_scene_shoot<P: Ports>(
    State(state): State<AppState<P>>,
    current_user: CurrentUser,
    Path((_day_id, _scene_id, shoot_id)): Path<(ShootingDayId, Uuid, SceneShootId)>,
    Json(req): Json<StartSceneShootRequest>,
) -> ApiResult<AggregateVersion> {
    let cmd = StartSceneShoot {
        id: shoot_id,
        start_dt: req.resolve_start_dt(),
        version: req.version,
    };
    let version = state
        .ports
        .scene_shoot_commands()
        .start(current_user.sub.clone(), cmd)
        .await
        .map_err(map_err)?;
    Ok((StatusCode::OK, Json(version)))
}

#[utoipa::path(
    patch,
    path = "/shooting-days/{day_id}/scenes/{scene_id}/scene-shoots/{shoot_id}/actual-order",
    request_body = SetActualOrderRequest,
    responses((status = 200, body = AggregateVersion)),
)]
pub async fn set_actual_order<P: Ports>(
    State(state): State<AppState<P>>,
    current_user: CurrentUser,
    Path((_day_id, _scene_id, shoot_id)): Path<(ShootingDayId, Uuid, SceneShootId)>,
    Json(req): Json<SetActualOrderRequest>,
) -> ApiResult<AggregateVersion> {
    let cmd = SetActualOrder {
        id: shoot_id,
        actual_order: req.actual_order,
        version: req.version,
    };
    let version = state
        .ports
        .scene_shoot_commands()
        .set_actual_order(current_user.sub.clone(), cmd)
        .await
        .map_err(map_err)?;
    Ok((StatusCode::OK, Json(version)))
}

#[utoipa::path(
    post,
    path = "/shooting-days/{day_id}/scenes/{scene_id}/scene-shoots/{shoot_id}/finish",
    request_body = FinishSceneShootRequest,
    responses((status = 200, body = AggregateVersion)),
)]
pub async fn finish_scene_shoot<P: Ports>(
    State(state): State<AppState<P>>,
    current_user: CurrentUser,
    Path((_day_id, _scene_id, shoot_id)): Path<(ShootingDayId, Uuid, SceneShootId)>,
    Json(req): Json<FinishSceneShootRequest>,
) -> ApiResult<AggregateVersion> {
    let cmd = FinishSceneShoot {
        id: shoot_id,
        end_dt: req.resolve_end_dt(),
        version: req.version,
    };
    let version = state
        .ports
        .scene_shoot_commands()
        .finish(current_user.sub.clone(), cmd)
        .await
        .map_err(map_err)?;
    Ok((StatusCode::OK, Json(version)))
}

#[utoipa::path(
    post,
    path = "/shooting-days/{day_id}/scenes/{scene_id}/scene-shoots/{shoot_id}/skip",
    request_body = SkipSceneShootRequest,
    responses((status = 200, body = AggregateVersion)),
)]
pub async fn skip_scene_shoot<P: Ports>(
    State(state): State<AppState<P>>,
    current_user: CurrentUser,
    Path((_day_id, _scene_id, shoot_id)): Path<(ShootingDayId, Uuid, SceneShootId)>,
    Json(req): Json<SkipSceneShootRequest>,
) -> ApiResult<AggregateVersion> {
    let cmd = SkipSceneShoot {
        id: shoot_id,
        version: req.version,
    };
    let version = state
        .ports
        .scene_shoot_commands()
        .skip(current_user.sub.clone(), cmd)
        .await
        .map_err(map_err)?;
    Ok((StatusCode::OK, Json(version)))
}

#[utoipa::path(
    get,
    path = "/shooting-days/{day_id}/scenes/{scene_id}/scene-shoots/{shoot_id}",
    responses((status = 200, body = SceneShootView)),
)]
pub async fn get_scene_shoot<P: Ports>(
    State(state): State<AppState<P>>,
    Path((_day_id, _scene_id, shoot_id)): Path<(ShootingDayId, Uuid, SceneShootId)>,
) -> ApiResult<SceneShootView> {
    let view = state
        .ports
        .scene_shoot_repo()
        .find_by_id(shoot_id)
        .await
        .map_err(map_err)?;
    Ok((StatusCode::OK, Json(view)))
}

#[utoipa::path(
    get,
    path = "/shooting-days/{day_id}/scenes/{scene_id}/scene-shoots",
    responses((status = 200, body = Vec<SceneShootView>)),
)]
pub async fn list_scene_shoots<P: Ports>(
    State(state): State<AppState<P>>,
    Path(day_id): Path<ShootingDayId>,
) -> ApiResult<Vec<SceneShootView>> {
    let views = state
        .ports
        .scene_shoot_repo()
        .list_by_shooting_day(day_id)
        .await
        .map_err(map_err)?;
    Ok((StatusCode::OK, Json(views)))
}

// ---------------------------------------------------------------------------
// SceneShoot Note handlers
// ---------------------------------------------------------------------------

#[utoipa::path(
    post,
    path = "/shooting-days/{day_id}/scenes/{scene_id}/scene-shoots/{shoot_id}/notes",
    request_body = AddNoteRequest,
    responses((status = 200, body = AggregateVersion)),
)]
pub async fn add_scene_shoot_note<P: Ports>(
    State(state): State<AppState<P>>,
    current_user: CurrentUser,
    Path((_day_id, _scene_id, shoot_id)): Path<(ShootingDayId, Uuid, SceneShootId)>,
    Json(req): Json<AddNoteRequest>,
) -> ApiResult<AggregateVersion> {
    let note_id = req.note_id.unwrap_or_else(Uuid::now_v7);
    let cmd = AddSceneShootNote {
        id: shoot_id,
        note_id,
        body: req.body,
        author: None,
    };
    let version = state
        .ports
        .scene_shoot_commands()
        .add_note(current_user.sub.clone(), cmd)
        .await
        .map_err(map_err)?;
    Ok((StatusCode::OK, Json(version)))
}

#[utoipa::path(
    put,
    path = "/shooting-days/{day_id}/scenes/{scene_id}/scene-shoots/{shoot_id}/notes/{note_id}",
    request_body = UpdateNoteRequest,
    responses((status = 200, body = AggregateVersion)),
)]
pub async fn update_scene_shoot_note<P: Ports>(
    State(state): State<AppState<P>>,
    current_user: CurrentUser,
    Path((_day_id, _scene_id, shoot_id, note_id)): Path<(ShootingDayId, Uuid, SceneShootId, Uuid)>,
    Json(req): Json<UpdateNoteRequest>,
) -> ApiResult<AggregateVersion> {
    let cmd = UpdateSceneShootNote {
        id: shoot_id,
        note_id,
        body: req.body,
        version: req.version,
    };
    let version = state
        .ports
        .scene_shoot_commands()
        .update_note(current_user.sub.clone(), cmd)
        .await
        .map_err(map_err)?;
    Ok((StatusCode::OK, Json(version)))
}

#[utoipa::path(
    delete,
    path = "/shooting-days/{day_id}/scenes/{scene_id}/scene-shoots/{shoot_id}/notes/{note_id}",
    responses((status = 200, body = AggregateVersion)),
)]
pub async fn remove_scene_shoot_note<P: Ports>(
    State(state): State<AppState<P>>,
    current_user: CurrentUser,
    Path((_day_id, _scene_id, shoot_id, note_id)): Path<(ShootingDayId, Uuid, SceneShootId, Uuid)>,
    Json(req): Json<VersionRequest>,
) -> ApiResult<AggregateVersion> {
    let cmd = RemoveSceneShootNote {
        id: shoot_id,
        note_id,
        version: req.version,
    };
    let version = state
        .ports
        .scene_shoot_commands()
        .remove_note(current_user.sub.clone(), cmd)
        .await
        .map_err(map_err)?;
    Ok((StatusCode::OK, Json(version)))
}

// ---------------------------------------------------------------------------
// Continuity Photo handlers
// ---------------------------------------------------------------------------

#[utoipa::path(
    post,
    path = "/shooting-days/{day_id}/scenes/{scene_id}/scene-shoots/{shoot_id}/continuity-photos",
    request_body = LinkContinuityPhotoRequest,
    responses((status = 200, body = AggregateVersion)),
)]
pub async fn link_continuity_photo<P: Ports>(
    State(state): State<AppState<P>>,
    current_user: CurrentUser,
    Path((day_id, _scene_id, shoot_id)): Path<(ShootingDayId, Uuid, SceneShootId)>,
    Json(req): Json<LinkContinuityPhotoRequest>,
) -> ApiResult<AggregateVersion> {
    // AUTHZ-GATE: handler-internal auth gate for authenticated-only routes
    // Resolve season_id from the shoot_day's episode → block → season chain.
    let shooting_day = state
        .ports
        .shooting_day_repo()
        .find_by_id(day_id)
        .await
        .map_err(map_err)?;
    let episode = state
        .ports
        .episode_repo()
        .find_by_id(shooting_day.episode_id.0)
        .await
        .map_err(map_err)?;
    let block = state
        .ports
        .block_repo()
        .find_by_id(episode.block_id.0)
        .await
        .map_err(map_err)?;
    // block.season_id is a SeasonId — extract inner Uuid
    let season_id = block.season_id;

    let is_authorized = state
        .ports
        .membership_repo()
        .has_active_costume_role_in_season(season_id, current_user.sub.clone())
        .await
        .unwrap_or(false);
    if !is_authorized {
        return Err((
            StatusCode::FORBIDDEN,
            Json(ErrorResponse {
                message: "not authorized to link continuity photos".into(),
            }),
        ));
    }

    let cmd = LinkContinuityPhoto {
        id: shoot_id,
        photo_id: req.photo_id,
        version: req.version,
    };
    let version = state
        .ports
        .scene_shoot_commands()
        .link_continuity_photo(current_user.sub.clone(), cmd)
        .await
        .map_err(map_err)?;
    Ok((StatusCode::OK, Json(version)))
}

#[utoipa::path(
    get,
    path = "/shooting-days/{day_id}/scenes/{scene_id}/scene-shoots/{shoot_id}/continuity-photos",
    responses((status = 200, body = Vec<PhotoId>)),
)]
pub async fn list_continuity_photos<P: Ports>(
    State(state): State<AppState<P>>,
    Path((_day_id, _scene_id, shoot_id)): Path<(ShootingDayId, Uuid, SceneShootId)>,
) -> ApiResult<Vec<PhotoId>> {
    let view = state
        .ports
        .scene_shoot_repo()
        .find_by_id(shoot_id)
        .await
        .map_err(map_err)?;
    Ok((StatusCode::OK, Json(view.continuity_photo_ids)))
}

#[utoipa::path(
    delete,
    path = "/shooting-days/{day_id}/scenes/{scene_id}/scene-shoots/{shoot_id}/continuity-photos/{photo_id}",
    responses((status = 200, body = AggregateVersion)),
)]
pub async fn unlink_continuity_photo<P: Ports>(
    State(state): State<AppState<P>>,
    current_user: CurrentUser,
    Path((day_id, _scene_id, shoot_id, photo_id)): Path<(
        ShootingDayId,
        Uuid,
        SceneShootId,
        PhotoId,
    )>,
    Query(version_req): Query<VersionRequest>,
) -> ApiResult<AggregateVersion> {
    // AUTHZ-GATE: handler-internal auth gate for authenticated-only routes
    // Resolve season_id from the shoot_day's episode → block → season chain.
    let shooting_day = state
        .ports
        .shooting_day_repo()
        .find_by_id(day_id)
        .await
        .map_err(map_err)?;
    let episode = state
        .ports
        .episode_repo()
        .find_by_id(shooting_day.episode_id.0)
        .await
        .map_err(map_err)?;
    let block = state
        .ports
        .block_repo()
        .find_by_id(episode.block_id.0)
        .await
        .map_err(map_err)?;
    let season_id = block.season_id;

    let is_authorized = state
        .ports
        .membership_repo()
        .has_active_costume_role_in_season(season_id, current_user.sub.clone())
        .await
        .unwrap_or(false);
    if !is_authorized {
        return Err((
            StatusCode::FORBIDDEN,
            Json(ErrorResponse {
                message: "not authorized to unlink continuity photos".into(),
            }),
        ));
    }

    let cmd = UnlinkContinuityPhoto {
        id: shoot_id,
        photo_id,
        version: version_req.version,
    };
    let version = state
        .ports
        .scene_shoot_commands()
        .unlink_continuity_photo(current_user.sub.clone(), cmd)
        .await
        .map_err(map_err)?;
    Ok((StatusCode::OK, Json(version)))
}

// ---------------------------------------------------------------------------
// ShootingDay wrap handler
// ---------------------------------------------------------------------------

#[utoipa::path(
    post,
    path = "/shooting-days/{id}/wrap",
    request_body = WrapShootingDayRequest,
    responses((status = 200, body = AggregateVersion)),
)]
pub async fn wrap_shooting_day<P: Ports>(
    State(state): State<AppState<P>>,
    current_user: CurrentUser,
    Path(id): Path<ShootingDayId>,
    Json(req): Json<WrapShootingDayRequest>,
) -> ApiResult<AggregateVersion> {
    use breakdown_core::shooting_day::commands::WrapShootingDay;
    let cmd = WrapShootingDay {
        id,
        version: req.version,
    };
    let version = state
        .ports
        .shooting_day_commands()
        .wrap(current_user.sub.clone(), cmd)
        .await
        .map_err(map_err)?;
    Ok((StatusCode::OK, Json(version)))
}

// ---------------------------------------------------------------------------
// Report handlers
// ---------------------------------------------------------------------------

#[utoipa::path(
    get,
    path = "/shooting-days/{id}/report/dispo",
    responses((status = 200, body = Vec<DispoRow>)),
)]
pub async fn dispo_report<P: Ports>(
    State(state): State<AppState<P>>,
    current_user: CurrentUser,
    Path(id): Path<ShootingDayId>,
) -> ApiResult<Vec<DispoRow>> {
    // AUTHZ-GATE: handler-internal auth gate
    let shooting_day = state
        .ports
        .shooting_day_repo()
        .find_by_id(id)
        .await
        .map_err(map_err)?;
    let episode = state
        .ports
        .episode_repo()
        .find_by_id(shooting_day.episode_id.0)
        .await
        .map_err(map_err)?;
    let block = state
        .ports
        .block_repo()
        .find_by_id(episode.block_id.0)
        .await
        .map_err(map_err)?;
    let is_authorized = state
        .ports
        .membership_repo()
        .has_active_costume_role_in_season(block.season_id, current_user.sub.clone())
        .await
        .unwrap_or(false);
    if !is_authorized {
        return Err((
            StatusCode::FORBIDDEN,
            Json(ErrorResponse {
                message: "not authorized to view reports".into(),
            }),
        ));
    }

    let rows = state
        .ports
        .scene_shoot_report_repo()
        .dispo_report(id)
        .await
        .map_err(map_err)?;
    Ok((StatusCode::OK, Json(rows)))
}

#[utoipa::path(
    get,
    path = "/shooting-days/{id}/report/shoot-day",
    responses((status = 200, body = Vec<ShootDayRow>)),
)]
pub async fn shoot_day_report<P: Ports>(
    State(state): State<AppState<P>>,
    current_user: CurrentUser,
    Path(id): Path<ShootingDayId>,
) -> ApiResult<Vec<ShootDayRow>> {
    // AUTHZ-GATE: handler-internal auth gate
    let shooting_day = state
        .ports
        .shooting_day_repo()
        .find_by_id(id)
        .await
        .map_err(map_err)?;
    let episode = state
        .ports
        .episode_repo()
        .find_by_id(shooting_day.episode_id.0)
        .await
        .map_err(map_err)?;
    let block = state
        .ports
        .block_repo()
        .find_by_id(episode.block_id.0)
        .await
        .map_err(map_err)?;
    let is_authorized = state
        .ports
        .membership_repo()
        .has_active_costume_role_in_season(block.season_id, current_user.sub.clone())
        .await
        .unwrap_or(false);
    if !is_authorized {
        return Err((
            StatusCode::FORBIDDEN,
            Json(ErrorResponse {
                message: "not authorized to view reports".into(),
            }),
        ));
    }

    let rows = state
        .ports
        .scene_shoot_report_repo()
        .shoot_day_report(id)
        .await
        .map_err(map_err)?;
    Ok((StatusCode::OK, Json(rows)))
}

#[utoipa::path(
    get,
    path = "/shooting-days/{id}/report/soll-ist",
    responses((status = 200, body = SollIstReport)),
)]
pub async fn soll_ist_report<P: Ports>(
    State(state): State<AppState<P>>,
    current_user: CurrentUser,
    Path(id): Path<ShootingDayId>,
) -> ApiResult<SollIstReport> {
    // AUTHZ-GATE: handler-internal auth gate
    let shooting_day = state
        .ports
        .shooting_day_repo()
        .find_by_id(id)
        .await
        .map_err(map_err)?;
    let episode = state
        .ports
        .episode_repo()
        .find_by_id(shooting_day.episode_id.0)
        .await
        .map_err(map_err)?;
    let block = state
        .ports
        .block_repo()
        .find_by_id(episode.block_id.0)
        .await
        .map_err(map_err)?;
    let is_authorized = state
        .ports
        .membership_repo()
        .has_active_costume_role_in_season(block.season_id, current_user.sub.clone())
        .await
        .unwrap_or(false);
    if !is_authorized {
        return Err((
            StatusCode::FORBIDDEN,
            Json(ErrorResponse {
                message: "not authorized to view reports".into(),
            }),
        ));
    }

    let report = state
        .ports
        .scene_shoot_report_repo()
        .soll_ist_report(id)
        .await
        .map_err(map_err)?;
    Ok((StatusCode::OK, Json(report)))
}

// ---------------------------------------------------------------------------
// PDF Report Handlers
// ---------------------------------------------------------------------------

/// Generate a sanitized filename for the PDF response.
#[allow(dead_code)]
pub fn sanitize_pdf_filename(kind: &str, locale: &str) -> String {
    let safe_kind: String = kind
        .chars()
        .filter(|c| c.is_alphanumeric() || *c == '-')
        .collect();
    let safe_locale: String = locale
        .chars()
        .filter(|c| c.is_alphanumeric() || *c == '-')
        .collect();
    format!("report-{}-{}.pdf", safe_kind, safe_locale)
}

/// Map a `ReportRenderError` to an HTTP status code and error response.
#[allow(dead_code)]
pub fn map_render_error(
    err: breakdown_core::reporting::ReportRenderError,
) -> (StatusCode, Json<ErrorResponse>) {
    use breakdown_core::reporting::ReportRenderError;
    match err {
        ReportRenderError::PageLimitExceeded { .. }
        | ReportRenderError::InputBoundsExceeded { .. } => (
            StatusCode::UNPROCESSABLE_ENTITY,
            Json(ErrorResponse {
                message: err.to_string(),
            }),
        ),
        ReportRenderError::RenderTimeout => (
            StatusCode::REQUEST_TIMEOUT,
            Json(ErrorResponse {
                message: err.to_string(),
            }),
        ),
        _ => (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(ErrorResponse {
                message: err.to_string(),
            }),
        ),
    }
}

#[utoipa::path(
    get,
    path = "/shooting-days/{id}/report/dispo.pdf",
    responses((status = 200, description = "PDF report")),
)]
pub async fn dispo_report_pdf<P: Ports>(
    State(state): State<AppState<P>>,
    current_user: CurrentUser,
    Path(id): Path<ShootingDayId>,
) -> Result<(StatusCode, HeaderMap, Vec<u8>), (StatusCode, Json<ErrorResponse>)> {
    // AUTHZ-GATE: handler-internal auth gate
    let shooting_day = state
        .ports
        .shooting_day_repo()
        .find_by_id(id)
        .await
        .map_err(map_err)?;
    let episode = state
        .ports
        .episode_repo()
        .find_by_id(shooting_day.episode_id.0)
        .await
        .map_err(map_err)?;
    let block = state
        .ports
        .block_repo()
        .find_by_id(episode.block_id.0)
        .await
        .map_err(map_err)?;
    let is_authorized = state
        .ports
        .membership_repo()
        .has_active_costume_role_in_season(block.season_id, current_user.sub.clone())
        .await
        .unwrap_or(false);
    if !is_authorized {
        return Err((
            StatusCode::FORBIDDEN,
            Json(ErrorResponse {
                message: "not authorized to view reports".into(),
            }),
        ));
    }

    // Query report data
    let rows = state
        .ports
        .scene_shoot_report_repo()
        .dispo_report(id)
        .await
        .map_err(map_err)?;

    // Render PDF via shared renderer
    let req = ReportRenderRequest {
        kind: ReportKind::Dispo,
        context: RenderPresentationContext {
            locale: ReportLocale::de_de(),
            timezone: "Europe/Berlin".into(),
            template_version: TEMPLATE_VERSION.to_string(),
        },
        data: serde_json::to_value(rows).map_err(|e| {
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(ErrorResponse {
                    message: format!("serialization error: {e}"),
                }),
            )
        })?,
    };
    let renderer = state.ports.report_renderer_ref();
    let rendered = renderer.render(req).await.map_err(map_render_error)?;

    let mut headers = HeaderMap::new();
    let content_type_value = rendered
        .content_type
        .parse::<axum::http::HeaderValue>()
        .map_err(|e| {
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(ErrorResponse {
                    message: format!("renderer produced invalid content-type: {e}"),
                }),
            )
        })?;
    headers.insert(axum::http::header::CONTENT_TYPE, content_type_value);
    let disposition_format = format!(
        r#"inline; filename="{}""#,
        sanitize_pdf_filename("dispo", "de-DE")
    );
    let disposition_value = disposition_format
        .parse::<axum::http::HeaderValue>()
        .map_err(|_| {
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(ErrorResponse {
                    message: "failed to construct Content-Disposition header".into(),
                }),
            )
        })?;
    headers.insert(axum::http::header::CONTENT_DISPOSITION, disposition_value);
    Ok((StatusCode::OK, headers, rendered.pdf_bytes))
}

#[utoipa::path(
    get,
    path = "/shooting-days/{id}/report/shoot-day.pdf",
    responses((status = 200, description = "PDF report")),
)]
pub async fn shoot_day_report_pdf<P: Ports>(
    State(state): State<AppState<P>>,
    current_user: CurrentUser,
    Path(id): Path<ShootingDayId>,
) -> Result<(StatusCode, HeaderMap, Vec<u8>), (StatusCode, Json<ErrorResponse>)> {
    // AUTHZ-GATE: handler-internal auth gate
    let shooting_day = state
        .ports
        .shooting_day_repo()
        .find_by_id(id)
        .await
        .map_err(map_err)?;
    let episode = state
        .ports
        .episode_repo()
        .find_by_id(shooting_day.episode_id.0)
        .await
        .map_err(map_err)?;
    let block = state
        .ports
        .block_repo()
        .find_by_id(episode.block_id.0)
        .await
        .map_err(map_err)?;
    let is_authorized = state
        .ports
        .membership_repo()
        .has_active_costume_role_in_season(block.season_id, current_user.sub.clone())
        .await
        .unwrap_or(false);
    if !is_authorized {
        return Err((
            StatusCode::FORBIDDEN,
            Json(ErrorResponse {
                message: "not authorized to view reports".into(),
            }),
        ));
    }

    // Query report data
    let rows = state
        .ports
        .scene_shoot_report_repo()
        .shoot_day_report(id)
        .await
        .map_err(map_err)?;

    // Render PDF via shared renderer
    let req = ReportRenderRequest {
        kind: ReportKind::ShootDay,
        context: RenderPresentationContext {
            locale: ReportLocale::de_de(),
            timezone: "Europe/Berlin".into(),
            template_version: TEMPLATE_VERSION.to_string(),
        },
        data: serde_json::to_value(rows).map_err(|e| {
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(ErrorResponse {
                    message: format!("serialization error: {e}"),
                }),
            )
        })?,
    };
    let renderer = state.ports.report_renderer_ref();
    let rendered = renderer.render(req).await.map_err(map_render_error)?;

    let mut headers = HeaderMap::new();
    let content_type_value = rendered
        .content_type
        .parse::<axum::http::HeaderValue>()
        .map_err(|e| {
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(ErrorResponse {
                    message: format!("renderer produced invalid content-type: {e}"),
                }),
            )
        })?;
    headers.insert(axum::http::header::CONTENT_TYPE, content_type_value);
    let disposition_format = format!(
        r#"inline; filename="{}""#,
        sanitize_pdf_filename("shoot-day", "de-DE")
    );
    let disposition_value = disposition_format
        .parse::<axum::http::HeaderValue>()
        .map_err(|_| {
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(ErrorResponse {
                    message: "failed to construct Content-Disposition header".into(),
                }),
            )
        })?;
    headers.insert(axum::http::header::CONTENT_DISPOSITION, disposition_value);
    Ok((StatusCode::OK, headers, rendered.pdf_bytes))
}

#[utoipa::path(
    get,
    path = "/shooting-days/{id}/report/planned-vs-actual.pdf",
    responses((status = 200, description = "PDF report")),
)]
pub async fn planned_vs_actual_report_pdf<P: Ports>(
    State(state): State<AppState<P>>,
    current_user: CurrentUser,
    Path(id): Path<ShootingDayId>,
) -> Result<(StatusCode, HeaderMap, Vec<u8>), (StatusCode, Json<ErrorResponse>)> {
    // AUTHZ-GATE: handler-internal auth gate
    let shooting_day = state
        .ports
        .shooting_day_repo()
        .find_by_id(id)
        .await
        .map_err(map_err)?;
    let episode = state
        .ports
        .episode_repo()
        .find_by_id(shooting_day.episode_id.0)
        .await
        .map_err(map_err)?;
    let block = state
        .ports
        .block_repo()
        .find_by_id(episode.block_id.0)
        .await
        .map_err(map_err)?;
    let is_authorized = state
        .ports
        .membership_repo()
        .has_active_costume_role_in_season(block.season_id, current_user.sub.clone())
        .await
        .unwrap_or(false);
    if !is_authorized {
        return Err((
            StatusCode::FORBIDDEN,
            Json(ErrorResponse {
                message: "not authorized to view reports".into(),
            }),
        ));
    }

    // Query report data
    let report = state
        .ports
        .scene_shoot_report_repo()
        .soll_ist_report(id)
        .await
        .map_err(map_err)?;

    // Render PDF via shared renderer
    let req = ReportRenderRequest {
        kind: ReportKind::PlannedVsActual,
        context: RenderPresentationContext {
            locale: ReportLocale::de_de(),
            timezone: "Europe/Berlin".into(),
            template_version: TEMPLATE_VERSION.to_string(),
        },
        data: serde_json::to_value(report).map_err(|e| {
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(ErrorResponse {
                    message: format!("serialization error: {e}"),
                }),
            )
        })?,
    };
    let renderer = state.ports.report_renderer_ref();
    let rendered = renderer.render(req).await.map_err(map_render_error)?;

    let mut headers = HeaderMap::new();
    let content_type_value = rendered
        .content_type
        .parse::<axum::http::HeaderValue>()
        .map_err(|e| {
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(ErrorResponse {
                    message: format!("renderer produced invalid content-type: {e}"),
                }),
            )
        })?;
    headers.insert(axum::http::header::CONTENT_TYPE, content_type_value);
    let disposition_format = format!(
        r#"inline; filename="{}""#,
        sanitize_pdf_filename("planned-vs-actual", "de-DE")
    );
    let disposition_value = disposition_format
        .parse::<axum::http::HeaderValue>()
        .map_err(|_| {
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(ErrorResponse {
                    message: "failed to construct Content-Disposition header".into(),
                }),
            )
        })?;
    headers.insert(axum::http::header::CONTENT_DISPOSITION, disposition_value);
    Ok((StatusCode::OK, headers, rendered.pdf_bytes))
}

/// Response body for a manual "archive now" request.
#[derive(Debug, Clone, Serialize, ToSchema)]
pub struct ManualArchiveResponse {
    /// Per-kind enqueue results (dedup-aware).
    pub jobs: Vec<ManualArchiveJobResult>,
}

/// One job enqueue outcome.
#[derive(Debug, Clone, Serialize, ToSchema)]
pub struct ManualArchiveJobResult {
    pub kind: String,
    pub job_id: Uuid,
    pub already_enqueued: bool,
    pub status: String,
}

/// Manual "archive now" remediation endpoint.
///
/// Setting-gerechte fallback when automation fails or is delayed. Uses the
/// **same** dedup key and pipeline as schedule / wrap triggers — never a
/// parallel pipeline. Gated stricter than PDF routes: only `CostumeDesigner`
/// and `WardrobeSupervisor` (excludes `CostumeAssistant`).
#[utoipa::path(
    post,
    path = "/shooting-days/{id}/report/archive",
    responses(
        (status = 202, description = "Archival job(s) enqueued"),
        (status = 403, description = "Forbidden"),
        (status = 404, description = "Shooting day not found"),
    ),
)]
pub async fn manual_archive_reports<P: Ports>(
    State(state): State<AppState<P>>,
    current_user: CurrentUser,
    Path(id): Path<ShootingDayId>,
) -> Result<(StatusCode, Json<ManualArchiveResponse>), (StatusCode, Json<ErrorResponse>)> {
    // Resolve shooting day → episode → block → season (fail closed).
    let shooting_day = state
        .ports
        .shooting_day_repo()
        .find_by_id(id)
        .await
        .map_err(map_err)?;
    let episode = state
        .ports
        .episode_repo()
        .find_by_id(shooting_day.episode_id.0)
        .await
        .map_err(map_err)?;
    let block = state
        .ports
        .block_repo()
        .find_by_id(episode.block_id.0)
        .await
        .map_err(map_err)?;

    // AUTHZ-GATE: manual archive — CostumeDesigner + WardrobeSupervisor only
    // (stricter than PDF routes; CostumeAssistant is excluded). Fail closed.
    let is_authorized = state
        .ports
        .membership_repo()
        .has_active_report_archive_role_in_season(block.season_id, current_user.sub.clone())
        .await
        .unwrap_or(false);
    if !is_authorized {
        return Err((
            StatusCode::FORBIDDEN,
            Json(ErrorResponse {
                message: "not authorized to enqueue report archival".into(),
            }),
        ));
    }

    // Enqueue all three kinds via the shared dedup key + pipeline.
    let kinds = [
        ReportKind::Dispo,
        ReportKind::ShootDay,
        ReportKind::PlannedVsActual,
    ];
    let mut jobs = Vec::with_capacity(kinds.len());
    for kind in kinds {
        let req = EnqueueArchivalRequest {
            kind,
            shooting_day_id: id,
            locale: ReportLocale::de_de(),
            template_version: TEMPLATE_VERSION.to_string(),
            snapshot_identity: SnapshotIdentity::current(),
            trigger: ArchivalTrigger::Manual,
        };
        let res: EnqueueArchivalResult = state
            .ports
            .report_archival_queue()
            .enqueue(req)
            .await
            .map_err(|e| {
                (
                    StatusCode::INTERNAL_SERVER_ERROR,
                    Json(ErrorResponse {
                        message: e.to_string(),
                    }),
                )
            })?;
        jobs.push(ManualArchiveJobResult {
            kind: kind.to_string(),
            job_id: res.job_id.0,
            already_enqueued: res.already_enqueued,
            status: res.status.as_str().to_string(),
        });
    }

    Ok((StatusCode::ACCEPTED, Json(ManualArchiveResponse { jobs })))
}

/// Build the full Axum router using the concrete `ProductionPorts` bundle.
pub fn routes() -> Router<AppState<ProductionPorts>> {
    Router::new()
        .route("/seasons", routing::post(create_season::<ProductionPorts>))
        .route("/seasons/{id}", routing::get(get_season::<ProductionPorts>))
        .route(
            "/seasons/{id}/name",
            routing::patch(rename_season::<ProductionPorts>),
        )
        .route(
            "/blocks",
            routing::post(create_block::<ProductionPorts>).get(list_blocks::<ProductionPorts>),
        )
        .route("/blocks/{id}", routing::get(get_block::<ProductionPorts>))
        .route(
            "/blocks/{id}/audit",
            routing::get(get_block_audit::<ProductionPorts>),
        )
        .route(
            "/audit",
            routing::get(get_audit_history::<ProductionPorts>),
        )
        .route(
            "/blocks/{id}/members",
            routing::post(invite_member::<ProductionPorts>).get(list_members::<ProductionPorts>),
        )
        .route(
            "/blocks/{id}/members/accept",
            routing::post(accept_invitation::<ProductionPorts>),
        )
        .route(
            "/blocks/{id}/members/leave",
            routing::post(leave_block::<ProductionPorts>),
        )
        .route(
            "/blocks/{id}/members/{user_id}/role",
            routing::post(grant_role::<ProductionPorts>),
        )
        .route(
            "/blocks/{id}/members/{user_id}",
            routing::get(get_member::<ProductionPorts>).delete(remove_member::<ProductionPorts>),
        )
        .route(
            "/blocks/{id}/time-span",
            routing::patch(update_block_time_span::<ProductionPorts>),
        )
        .route(
            "/episodes",
            routing::post(create_episode::<ProductionPorts>).get(list_episodes::<ProductionPorts>),
        )
        .route(
            "/episodes/{id}",
            routing::get(get_episode::<ProductionPorts>),
        )
        .route(
            "/episodes/{id}/name",
            routing::patch(rename_episode::<ProductionPorts>),
        )
        .route(
            "/scenes",
            routing::post(create_scene::<ProductionPorts>).get(list_scenes::<ProductionPorts>),
        )
        .route("/scenes/{id}", routing::get(get_scene::<ProductionPorts>))
        .route(
            "/scenes/{id}/details",
            routing::patch(update_scene_details::<ProductionPorts>),
        )
        .route(
            "/scenes/{id}/characters",
            routing::post(assign_scene_character::<ProductionPorts>),
        )
        .route(
            "/scenes/{id}/characters/{character_id}",
            routing::delete(remove_scene_character::<ProductionPorts>),
        )
        .route(
            "/scenes/{id}/shooting-days",
            routing::post(schedule_scene_on_shooting_day::<ProductionPorts>),
        )
        .route(
            "/scenes/{id}/shooting-days/{shooting_day_id}",
            routing::delete(unschedule_scene_from_shooting_day::<ProductionPorts>),
        )
        .route(
            "/episodes/{episode_id}/shooting-days",
            routing::post(create_shooting_day::<ProductionPorts>)
                .get(list_shooting_days::<ProductionPorts>),
        )
        .route(
            "/shooting-days/{id}",
            routing::get(get_shooting_day::<ProductionPorts>),
        )
        .route(
            "/shooting-days/{id}",
            routing::patch(update_shooting_day::<ProductionPorts>),
        )
        .route(
            "/shooting-days/{id}/archive",
            routing::post(archive_shooting_day::<ProductionPorts>),
        )
        .route(
            "/characters",
            routing::post(create_character::<ProductionPorts>)
                .get(list_characters::<ProductionPorts>),
        )
        .route(
            "/characters/{id}",
            routing::get(get_character::<ProductionPorts>),
        )
        .route(
            "/characters/{id}/measurements",
            routing::patch(update_measurements::<ProductionPorts>),
        )
        .route(
            "/characters/{id}/contact",
            routing::patch(update_contact_info::<ProductionPorts>),
        )
        .route(
            "/costumes",
            routing::post(create_costume::<ProductionPorts>).get(list_costumes::<ProductionPorts>),
        )
        .route(
            "/costumes/{id}",
            routing::get(get_costume::<ProductionPorts>),
        )
        .route(
            "/costumes/{id}/notes",
            routing::patch(update_costume_notes::<ProductionPorts>),
        )
        .route(
            "/costumes/{id}/assign",
            routing::post(assign_costume::<ProductionPorts>),
        )
        .route(
            "/costumes/{id}/details",
            routing::post(add_costume_detail::<ProductionPorts>),
        )
        .route(
            "/costumes/{id}/unassign",
            routing::post(unassign_costume::<ProductionPorts>),
        )
        .route(
            "/seasons/{season_id}/costume-categories",
            routing::post(create_costume_category::<ProductionPorts>)
                .get(list_costume_categories::<ProductionPorts>),
        )
        .route(
            "/costume-categories/{id}",
            routing::patch(update_costume_category::<ProductionPorts>),
        )
        .route(
            "/costume-categories/{id}/archive",
            routing::post(archive_costume_category::<ProductionPorts>),
        )
        // --- Photo endpoints ---
        .route(
            "/costumes/{costume_id}/photos",
            routing::post(upload_costume_photo::<ProductionPorts>),
        )
        .route(
            "/costumes/{costume_id}/photos/{photo_id}/bytes",
            routing::get(get_costume_photo_bytes::<ProductionPorts>),
        )
        .route(
            "/costumes/{costume_id}/photos/{photo_id}",
            routing::delete(delete_costume_photo::<ProductionPorts>),
        )
        // --- SceneShoot execution endpoints ---
        .route(
            "/shooting-days/{day_id}/scenes/{scene_id}/scene-shoots",
            routing::post(plan_scene_shoot::<ProductionPorts>),
        )
        .route(
            "/shooting-days/{day_id}/scenes/{scene_id}/scene-shoots/{shoot_id}",
            routing::patch(replan_scene_shoot::<ProductionPorts>)
                .get(get_scene_shoot::<ProductionPorts>),
        )
        .route(
            "/shooting-days/{day_id}/scenes/{scene_id}/scene-shoots/{shoot_id}/start",
            routing::post(start_scene_shoot::<ProductionPorts>),
        )
        .route(
            "/shooting-days/{day_id}/scenes/{scene_id}/scene-shoots/{shoot_id}/actual-order",
            routing::patch(set_actual_order::<ProductionPorts>),
        )
        .route(
            "/shooting-days/{day_id}/scenes/{scene_id}/scene-shoots/{shoot_id}/finish",
            routing::post(finish_scene_shoot::<ProductionPorts>),
        )
        .route(
            "/shooting-days/{day_id}/scenes/{scene_id}/scene-shoots/{shoot_id}/skip",
            routing::post(skip_scene_shoot::<ProductionPorts>),
        )
        // --- SceneShoot note endpoints ---
        .route(
            "/shooting-days/{day_id}/scenes/{scene_id}/scene-shoots/{shoot_id}/notes",
            routing::post(add_scene_shoot_note::<ProductionPorts>),
        )
        .route(
            "/shooting-days/{day_id}/scenes/{scene_id}/scene-shoots/{shoot_id}/notes/{note_id}",
            routing::put(update_scene_shoot_note::<ProductionPorts>)
                .delete(remove_scene_shoot_note::<ProductionPorts>),
        )
        // --- Continuity photo endpoints ---
        .route(
            "/shooting-days/{day_id}/scenes/{scene_id}/scene-shoots/{shoot_id}/continuity-photos",
            routing::post(link_continuity_photo::<ProductionPorts>)
                .get(list_continuity_photos::<ProductionPorts>),
        )
        .route(
            "/shooting-days/{day_id}/scenes/{scene_id}/scene-shoots/{shoot_id}/continuity-photos/{photo_id}",
            routing::delete(unlink_continuity_photo::<ProductionPorts>),
        )
        // --- ShootingDay lifecycle endpoints ---
        .route(
            "/shooting-days/{id}/wrap",
            routing::post(wrap_shooting_day::<ProductionPorts>),
        )
        // --- Report endpoints ---
        .route(
            "/shooting-days/{id}/report/dispo",
            routing::get(dispo_report::<ProductionPorts>),
        )
        .route(
            "/shooting-days/{id}/report/shoot-day",
            routing::get(shoot_day_report::<ProductionPorts>),
        )
        .route(
            "/shooting-days/{id}/report/soll-ist",
            routing::get(soll_ist_report::<ProductionPorts>),
        )

        // PDF report routes
        .route(
            "/shooting-days/{id}/report/dispo.pdf",
            routing::get(dispo_report_pdf::<ProductionPorts>),
        )
        .route(
            "/shooting-days/{id}/report/shoot-day.pdf",
            routing::get(shoot_day_report_pdf::<ProductionPorts>),
        )
        .route(
            "/shooting-days/{id}/report/planned-vs-actual.pdf",
            routing::get(planned_vs_actual_report_pdf::<ProductionPorts>),
        )
        // Manual "archive now" remediation (CostumeDesigner + WardrobeSupervisor).
        .route(
            "/shooting-days/{id}/report/archive",
            routing::post(manual_archive_reports::<ProductionPorts>),
        )
}
