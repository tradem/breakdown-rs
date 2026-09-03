// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: gpt-5.6-luna (opencode-go)
// Co-authored-by: deepseek-v4-flash (opencode-go)
// Co-authored-by: glm-5.2 (neuralwatt)
// Co-authored-by: longcat-2.0-free (opencode)

//! Axum-Handler (Request → Command / Query)

// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: mimo-v2.5 (opencode-go)
// Co-authored-by: hy3 (opencode-go)
// Co-authored-by: hy4-preview (opencode-go)

use std::collections::HashMap;
use std::sync::Arc;

use crate::problems::{ApiError, Bytes, Json, Path, ProblemDetails, Query};
use axum::extract::{DefaultBodyLimit, State};
use axum::http::{HeaderMap, HeaderValue, StatusCode, header};
use axum::response::{IntoResponse, Response};
use axum::{Router, routing};
use breakdown_core::ai::{
    AiConfigCommands, AiConfigRepository, AiConfigView, AiImportEnqueueRequest,
    AiImportEnqueueResult, AiImportJobId, AiImportQueue, ApplyMapping, CreateAiConfig,
    DocumentKind, LlmProvider, MergedPreview, ModelInfo, RevokeAiConfig, ScriptContext,
    SourceFormat, Telemetry, TelemetryApplyState, UpdateAiConfig,
};
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
use breakdown_core::error_registry::MEMBERSHIP_NOT_FOUND;
use breakdown_core::membership::policy::{Action, PolicyDecision, SeasonAuthContext};
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
use breakdown_core::settings::commands::{
    CreateCredentialBinding, RevokeCredential, RotateCredentialBinding,
};
use breakdown_core::settings::ports::{
    CredentialVault, GDriveCredentialBundle, SecretValue, SettingsCommands, SettingsRepository,
};
use breakdown_core::settings::views::SettingsView;
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
use sha2::{Digest, Sha256};
use utoipa::{IntoParams, ToSchema};
use uuid::Uuid;

// The `AiDocumentStore` / `AiPreviewStore` traits are imported for method
// resolution on the generic `P::AiDocumentStore` / `P::AiPreviewStore`
// associated types (issue #176).
use infra::ai::{
    AiDocumentStore, AiPreviewStore, ApplyScriptRequest, ApplyWorker, ScheduleApplyRequest,
    ScheduleApplyWorker,
};

use crate::auth::CurrentUser;
use crate::state::{AppState, Ports, ProductionPorts};

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

// `IntoParams` so handlers that take it as a `Query` extractor (rather than a
// JSON body) document the `version` query parameter — utoipa only infers query
// parameters for `IntoParams` types, and a silently undocumented parameter
// means the generated client would never send the optimistic-locking version.
#[derive(Debug, Clone, Deserialize, ToSchema, IntoParams)]
pub struct VersionRequest {
    pub version: AggregateVersion,
}

/// Generic credential submission kept for non-GDrive providers. GDrive uses
/// the typed write-only request below so its complete bundle is stored as one
/// Vault binding.
#[derive(Clone, Deserialize, ToSchema)]
pub struct CreateCredentialRequest {
    pub provider: String,
    pub secret: String,
}

/// Write-only GDrive credentials. This type intentionally does not implement
/// `Debug` or `Serialize`; it is converted immediately at the API edge into a
/// non-serializable `GDriveCredentialBundle`.
#[derive(Deserialize, ToSchema)]
pub struct GDriveCredentialRequest {
    pub client_id: String,
    pub client_secret: String,
    pub refresh_token: String,
    pub root_folder_id: Option<String>,
}

impl GDriveCredentialRequest {
    fn into_bundle(self) -> Result<GDriveCredentialBundle, DomainError> {
        GDriveCredentialBundle::try_new(
            self.client_id,
            self.client_secret,
            self.refresh_token,
            self.root_folder_id,
        )
    }
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

type ApiResult<T> = Result<(StatusCode, Json<T>), ApiError>;

/// Required `episode_id` query parameter (ADR-031 D3: missing/invalid query
/// params are `http.bad-query-param`, 400).
fn require_episode(params: &ListParams) -> Result<EpisodeId, ApiError> {
    params
        .episode_id
        .ok_or(ApiError::BadQueryParam("episode_id is required"))
}

/// Required `season_id` query parameter (`http.bad-query-param`, 400).
fn require_season(params: &ListParams) -> Result<SeasonId, ApiError> {
    params
        .season_id
        .ok_or(ApiError::BadQueryParam("season_id is required"))
}

/// Required `series_id` query parameter (`http.bad-query-param`, 400).
fn require_series(params: &ListParams) -> Result<SeriesId, ApiError> {
    params
        .series_id
        .ok_or(ApiError::BadQueryParam("series_id is required"))
}

/// Resolve the `series_id` for a scene at the API edge (scene → episode → series).
///
/// Handlers are the legitimate read-model boundary: the `series_id` is carried
/// into the command for the `EventMetadata` audit trail and must never be
/// re-queried by the command adapter (CQRS, issue #147). A missing parent
/// projection is a genuine 404 — the entity cannot exist without it.
async fn series_id_for_scene<P: Ports>(
    state: &AppState<P>,
    scene_id: Uuid,
) -> Result<SeriesId, ApiError> {
    let scene = state.ports.scene_repo().find_by_id(scene_id).await?;
    let episode = state
        .ports
        .episode_repo()
        .find_by_id(scene.episode_id.0)
        .await?;
    Ok(episode.series_id)
}

/// Resolve the `series_id` for a shooting day (shooting_day → episode → series).
async fn series_id_for_shooting_day<P: Ports>(
    state: &AppState<P>,
    day_id: ShootingDayId,
) -> Result<SeriesId, ApiError> {
    let day = state.ports.shooting_day_repo().find_by_id(day_id).await?;
    let episode = state
        .ports
        .episode_repo()
        .find_by_id(day.episode_id.0)
        .await?;
    Ok(episode.series_id)
}

/// Resolve the `series_id` for a character (character → season → series).
async fn series_id_for_character<P: Ports>(
    state: &AppState<P>,
    character_id: Uuid,
) -> Result<SeriesId, ApiError> {
    let ch = state
        .ports
        .character_repo()
        .find_by_id(character_id)
        .await?;
    let season = state.ports.season_repo().find_by_id(ch.season_id.0).await?;
    Ok(season.series_id)
}

/// Resolve the `series_id` for a costume category (category → season → series).
async fn series_id_for_costume_category<P: Ports>(
    state: &AppState<P>,
    category_id: Uuid,
) -> Result<SeriesId, ApiError> {
    let cc = state
        .ports
        .costume_category_repo()
        .find_by_id(category_id)
        .await?;
    let season = state.ports.season_repo().find_by_id(cc.season_id.0).await?;
    Ok(season.series_id)
}

/// Resolve the `series_id` for a scene shoot (scene_shoot → scene → episode → series).
async fn series_id_for_scene_shoot<P: Ports>(
    state: &AppState<P>,
    shoot_id: SceneShootId,
) -> Result<SeriesId, ApiError> {
    let ss = state.ports.scene_shoot_repo().find_by_id(shoot_id).await?;
    let scene = state.ports.scene_repo().find_by_id(ss.scene_id).await?;
    let episode = state
        .ports
        .episode_repo()
        .find_by_id(scene.episode_id.0)
        .await?;
    Ok(episode.series_id)
}

/// Resolve the (optional) `series_id` for a costume
/// (costume → character(opt) → season → series).
///
/// `Ok(None)` when the costume is unassigned (mirrors the pre-migration
/// adapter semantics); hard-404 when the costume itself is missing.
async fn series_id_for_costume<P: Ports>(
    state: &AppState<P>,
    costume_id: Uuid,
) -> Result<Option<SeriesId>, ApiError> {
    let costume = state.ports.costume_repo().find_by_id(costume_id).await?;
    match costume.character_id {
        Some(character_id) => {
            let ch = state
                .ports
                .character_repo()
                .find_by_id(character_id)
                .await?;
            let season = state.ports.season_repo().find_by_id(ch.season_id.0).await?;
            Ok(Some(season.series_id))
        }
        None => Ok(None),
    }
}

#[utoipa::path(
    get,
    path = "/audit",
    params(ListParams),
    responses(
        (status = 200, body = Vec<AuditEntry>, description = "Audit journal entries, newest first"),
        (status = 403, body = ProblemDetails, description = "Not authorized"),
        (status = 422, body = ProblemDetails, description = "Validation error"),
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
        .await?;
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
        .await?;
    Ok((StatusCode::CREATED, Json(IdVersionResponse { id, version })))
}

#[utoipa::path(
    get,
    path = "/seasons/{id}",
    params(("id" = Uuid, Path, description = "Season id")),
    responses((status = 200, body = SeasonView), (status = 404, body = ProblemDetails)),
)]
pub async fn get_season<P: Ports>(
    State(state): State<AppState<P>>,
    Path(id): Path<Uuid>,
) -> ApiResult<SeasonView> {
    let view = state.ports.season_repo().find_by_id(id).await?;
    Ok((StatusCode::OK, Json(view)))
}

/// Season membership DTO — the single source of truth for the client-side
/// AUTHZ-GATE (D2 of the `wire-flutter-oidc-auth` change).
///
/// `has_active_costume_role_in_season` is the backend-computed predicate the
/// client must NOT re-implement (CQRS-boundary rule). `capabilities` is derived
/// server-side from the caller's active costume-dept role; the client consumes
/// it with strict parsing (unknown entries reject the DTO).
#[derive(Debug, Clone, Serialize, ToSchema)]
pub struct SeasonMembershipDto {
    pub season_id: Uuid,
    pub has_active_costume_role_in_season: bool,
    #[schema(value_type = Vec<String>)]
    pub capabilities: Vec<String>,
}

/// Derive the caller's season-scoped capabilities from their active costume-dept
/// role.
///
/// v1 maps a single boolean (`has_active_costume_role_in_season`) to the full
/// capability set: a costumer with any active costume-dept role in the season
/// can both upload continuity photos and assign costumes. Future role-distinct
/// policies can split this without changing the DTO surface.
fn derive_capabilities(has_active_costume_role_in_season: bool) -> Vec<String> {
    if has_active_costume_role_in_season {
        vec![
            "upload_continuity_photos".to_string(),
            "assign_costumes".to_string(),
        ]
    } else {
        Vec::new()
    }
}

#[utoipa::path(
    get,
    path = "/seasons/{id}/membership",
    params(("id" = Uuid, Path, description = "Season id")),
    responses(
        (status = 200, body = SeasonMembershipDto, description = "Membership of the authenticated caller in the season"),
        (status = 401, body = ProblemDetails, description = "Authentication required"),
        (status = 404, body = ProblemDetails, description = "Season not found"),
    ),
)]
pub async fn get_season_membership<P: Ports>(
    State(state): State<AppState<P>>,
    current_user: CurrentUser,
    Path(id): Path<Uuid>,
) -> ApiResult<SeasonMembershipDto> {
    // Verify the season exists — returns `season.not-found` (404) on miss. The
    // API edge is the only legitimate consumer of this read-model query
    // (CQRS-boundary rule).
    let season = state.ports.season_repo().find_by_id(id).await?;

    // Backend-computed membership predicate — the single source of truth for
    // the client-side AUTHZ-GATE.
    let has_role = state
        .ports
        .membership_repo()
        .has_active_costume_role_in_season(SeasonId::from_uuid(season.id), current_user.sub.clone())
        .await?;

    Ok((
        StatusCode::OK,
        Json(SeasonMembershipDto {
            season_id: id,
            has_active_costume_role_in_season: has_role,
            capabilities: derive_capabilities(has_role),
        }),
    ))
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
    let series_id = Some(state.ports.season_repo().find_by_id(id).await?.series_id);
    let cmd = RenameSeason {
        id,
        title: req.title,
        series_id,
        version: req.version,
    };
    let version = state
        .ports
        .season_commands()
        .rename(current_user.sub.clone(), cmd)
        .await?;
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
        .await?;

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
        tracing::error!(error = %e, "failed to bootstrap block owner");
        return Err(ApiError::Internal);
    }

    Ok((StatusCode::CREATED, Json(IdVersionResponse { id, version })))
}

#[utoipa::path(
    get,
    path = "/blocks/{id}",
    params(("id" = Uuid, Path, description = "Block id")),
    responses((status = 200, body = BlockView), (status = 404, body = ProblemDetails)),
)]
pub async fn get_block<P: Ports>(
    State(state): State<AppState<P>>,
    Path(id): Path<Uuid>,
) -> ApiResult<BlockView> {
    let view = state.ports.block_repo().find_by_id(id).await?;
    Ok((StatusCode::OK, Json(view)))
}

#[utoipa::path(
    get,
    path = "/blocks/{id}/audit",
    params(("id" = Uuid, Path, description = "Block id"), ListParams),
    responses(
        (status = 200, body = Vec<AuditEntry>, description = "Audit journal entries for the block, newest first"),
        (status = 403, body = ProblemDetails, description = "Caller is not an active member of the active block (X-Active-Block header)"),
        (status = 400, body = ProblemDetails, description = "Missing or malformed X-Active-Block header"),
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
        .await?;
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
        .await?;
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
    let series_id = Some(state.ports.block_repo().find_by_id(id).await?.series_id);
    let cmd = UpdateBlockTimeSpan {
        id,
        start_date: req.start_date,
        end_date: req.end_date,
        series_id,
        version: req.version,
    };
    let version = state
        .ports
        .block_commands()
        .update_time_span(current_user.sub.clone(), cmd)
        .await?;
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
        .await?;
    Ok((StatusCode::CREATED, Json(IdVersionResponse { id, version })))
}

#[utoipa::path(
    get,
    path = "/episodes/{id}",
    params(("id" = Uuid, Path, description = "Episode id")),
    responses((status = 200, body = EpisodeView), (status = 404, body = ProblemDetails)),
)]
pub async fn get_episode<P: Ports>(
    State(state): State<AppState<P>>,
    Path(id): Path<Uuid>,
) -> ApiResult<EpisodeView> {
    let view = state.ports.episode_repo().find_by_id(id).await?;
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
        .await?;
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
    let series_id = Some(state.ports.episode_repo().find_by_id(id).await?.series_id);
    let cmd = RenameEpisode {
        id,
        name: req.name,
        series_id,
        version: req.version,
    };
    let version = state
        .ports
        .episode_commands()
        .rename(current_user.sub.clone(), cmd)
        .await?;
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
        (status = 422, description = "Validation error", body = ProblemDetails),
        (status = 409, description = "Conflict", body = ProblemDetails),
    )
)]
pub async fn create_scene<P: Ports>(
    State(state): State<AppState<P>>,
    current_user: CurrentUser,
    Json(req): Json<CreateSceneRequest>,
) -> ApiResult<IdVersionResponse> {
    let id = Uuid::now_v7();
    let series_id = Some(
        state
            .ports
            .episode_repo()
            .find_by_id(req.episode_id.0)
            .await?
            .series_id,
    );
    let cmd = CreateScene {
        id,
        episode_id: req.episode_id,
        series_id,
        details: req.details,
    };
    let (id, version) = state
        .ports
        .scene_commands()
        .create(current_user.sub.clone(), cmd)
        .await?;
    Ok((StatusCode::CREATED, Json(IdVersionResponse { id, version })))
}

#[utoipa::path(
    get,
    path = "/scenes/{id}",
    params(("id" = Uuid, Path, description = "Scene id")),
    responses(
        (status = 200, body = SceneView),
        (status = 404, body = ProblemDetails),
    )
)]
pub async fn get_scene<P: Ports>(
    State(state): State<AppState<P>>,
    Path(id): Path<Uuid>,
) -> ApiResult<SceneView> {
    let view = state.ports.scene_repo().find_by_id(id).await?;
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
        .await?;
    Ok((StatusCode::OK, Json(views)))
}

#[utoipa::path(
    patch,
    path = "/scenes/{id}/details",
    request_body = UpdateSceneDetailsRequest,
    responses(
        (status = 200, body = AggregateVersion),
        (status = 404, body = ProblemDetails),
        (status = 409, body = ProblemDetails),
    )
)]
pub async fn update_scene_details<P: Ports>(
    State(state): State<AppState<P>>,
    current_user: CurrentUser,
    Path(id): Path<Uuid>,
    Json(req): Json<UpdateSceneDetailsRequest>,
) -> ApiResult<AggregateVersion> {
    let series_id = Some(series_id_for_scene(&state, id).await?);
    let cmd = UpdateSceneDetails {
        id,
        details: req.details,
        series_id,
        version: req.version,
    };
    let version = state
        .ports
        .scene_commands()
        .update_details(current_user.sub.clone(), cmd)
        .await?;
    Ok((StatusCode::OK, Json(version)))
}

#[utoipa::path(
    post,
    path = "/scenes/{id}/characters",
    request_body = AssignCharacterRequest,
    responses((status = 200, body = AggregateVersion), (status = 409, body = ProblemDetails)),
)]
pub async fn assign_scene_character<P: Ports>(
    State(state): State<AppState<P>>,
    current_user: CurrentUser,
    Path(id): Path<Uuid>,
    Json(req): Json<AssignCharacterRequest>,
) -> ApiResult<AggregateVersion> {
    let series_id = Some(series_id_for_scene(&state, id).await?);
    let cmd = AssignCharacter {
        id,
        character_id: req.character_id,
        series_id,
        version: req.version,
    };
    let version = state
        .ports
        .scene_commands()
        .assign_character(current_user.sub.clone(), cmd)
        .await?;
    Ok((StatusCode::OK, Json(version)))
}

#[utoipa::path(
    delete,
    path = "/scenes/{id}/characters/{character_id}",
    params(("id" = Uuid, Path), ("character_id" = Uuid, Path)),
    responses((status = 200, body = AggregateVersion), (status = 409, body = ProblemDetails)),
)]
pub async fn remove_scene_character<P: Ports>(
    State(state): State<AppState<P>>,
    current_user: CurrentUser,
    Path((id, character_id)): Path<(Uuid, Uuid)>,
    Query(version): Query<VersionRequest>,
) -> ApiResult<AggregateVersion> {
    let series_id = Some(series_id_for_scene(&state, id).await?);
    let cmd = RemoveCharacter {
        id,
        character_id,
        series_id,
        version: version.version,
    };
    let version = state
        .ports
        .scene_commands()
        .remove_character(current_user.sub.clone(), cmd)
        .await?;
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
    let series_id = Some(
        state
            .ports
            .episode_repo()
            .find_by_id(episode_id.0)
            .await?
            .series_id,
    );
    let cmd = CreateShootingDay {
        id,
        episode_id,
        series_id,
        label: req.label,
        order_key: req.order_key,
        date: req.date,
        source: req.source,
    };
    let (id, version) = state
        .ports
        .shooting_day_commands()
        .create(current_user.sub.clone(), cmd)
        .await?;
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
        .await?;
    Ok((StatusCode::OK, Json(views)))
}

#[utoipa::path(
    get,
    path = "/shooting-days/{id}",
    params(("id" = ShootingDayId, Path, description = "Shooting day id")),
    responses((status = 200, body = ShootingDayView), (status = 404, body = ProblemDetails)),
)]
pub async fn get_shooting_day<P: Ports>(
    State(state): State<AppState<P>>,
    Path(id): Path<ShootingDayId>,
) -> ApiResult<ShootingDayView> {
    let view = state.ports.shooting_day_repo().find_by_id(id).await?;
    Ok((StatusCode::OK, Json(view)))
}

#[utoipa::path(
    patch,
    path = "/shooting-days/{id}",
    params(("id" = ShootingDayId, Path, description = "Shooting day id")),
    request_body = UpdateShootingDayRequest,
    responses(
        (status = 200, body = AggregateVersion),
        (status = 422, description = "No update field provided"),
        (status = 409, body = ProblemDetails),
    ),
)]
pub async fn update_shooting_day<P: Ports>(
    State(state): State<AppState<P>>,
    current_user: CurrentUser,
    Path(id): Path<ShootingDayId>,
    Json(req): Json<UpdateShootingDayRequest>,
) -> ApiResult<AggregateVersion> {
    let actor = current_user.sub.clone();
    let series_id = Some(series_id_for_shooting_day(&state, id).await?);
    let cmds = state.ports.shooting_day_commands();
    if let Some(order_key) = req.order_key {
        let version = cmds
            .reorder(
                actor.clone(),
                ReorderShootingDay {
                    id,
                    order_key,
                    series_id,
                    version: req.version,
                },
            )
            .await?;
        return Ok((StatusCode::OK, Json(version)));
    }
    if req.date.is_some() {
        let version = cmds
            .reschedule(
                actor.clone(),
                RescheduleShootingDay {
                    id,
                    date: req.date,
                    series_id,
                    version: req.version,
                },
            )
            .await?;
        return Ok((StatusCode::OK, Json(version)));
    }
    if req.label.is_some() {
        let version = cmds
            .rename(
                actor,
                RenameShootingDay {
                    id,
                    label: req.label,
                    series_id,
                    version: req.version,
                },
            )
            .await?;
        return Ok((StatusCode::OK, Json(version)));
    }
    Err(ApiError::Validation(
        "no update field provided (order_key, date, or label)",
    ))
}

#[utoipa::path(
    post,
    path = "/shooting-days/{id}/archive",
    params(("id" = ShootingDayId, Path, description = "Shooting day id")),
    request_body = VersionRequest,
    responses((status = 200, body = AggregateVersion), (status = 409, body = ProblemDetails)),
)]
pub async fn archive_shooting_day<P: Ports>(
    State(state): State<AppState<P>>,
    current_user: CurrentUser,
    Path(id): Path<ShootingDayId>,
    Json(req): Json<VersionRequest>,
) -> ApiResult<AggregateVersion> {
    let series_id = Some(series_id_for_shooting_day(&state, id).await?);
    let version = state
        .ports
        .shooting_day_commands()
        .archive(
            current_user.sub.clone(),
            ArchiveShootingDay {
                id,
                series_id,
                version: req.version,
            },
        )
        .await?;
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
    responses((status = 200, body = AggregateVersion), (status = 409, body = ProblemDetails)),
)]
pub async fn schedule_scene_on_shooting_day<P: Ports>(
    State(state): State<AppState<P>>,
    current_user: CurrentUser,
    Path(id): Path<Uuid>,
    Json(req): Json<ScheduleSceneRequest>,
) -> ApiResult<AggregateVersion> {
    let series_id = Some(series_id_for_shooting_day(&state, req.shooting_day_id).await?);
    let cmd = ScheduleSceneOnShootingDay {
        id,
        shooting_day_id: req.shooting_day_id,
        series_id,
        version: req.version,
    };
    let version = state
        .ports
        .scene_commands()
        .schedule_on_shooting_day(current_user.sub.clone(), cmd)
        .await?;
    Ok((StatusCode::OK, Json(version)))
}

#[utoipa::path(
    delete,
    path = "/scenes/{id}/shooting-days/{shooting_day_id}",
    params(
        ("id" = Uuid, Path, description = "Scene id"),
        ("shooting_day_id" = ShootingDayId, Path, description = "Shooting day id")
    ),
    responses((status = 200, body = AggregateVersion), (status = 409, body = ProblemDetails)),
)]
pub async fn unschedule_scene_from_shooting_day<P: Ports>(
    State(state): State<AppState<P>>,
    current_user: CurrentUser,
    Path((id, shooting_day_id)): Path<(Uuid, ShootingDayId)>,
    Query(version): Query<VersionRequest>,
) -> ApiResult<AggregateVersion> {
    let series_id = Some(series_id_for_shooting_day(&state, shooting_day_id).await?);
    let cmd = UnscheduleSceneFromShootingDay {
        id,
        shooting_day_id,
        series_id,
        version: version.version,
    };
    let version = state
        .ports
        .scene_commands()
        .unschedule_from_shooting_day(current_user.sub.clone(), cmd)
        .await?;
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
        (status = 422, description = "Validation error", body = ProblemDetails),
    )
)]
pub async fn create_character<P: Ports>(
    State(state): State<AppState<P>>,
    current_user: CurrentUser,
    Json(req): Json<CreateCharacterRequest>,
) -> ApiResult<IdVersionResponse> {
    let id = Uuid::now_v7();
    let series_id = Some(
        state
            .ports
            .season_repo()
            .find_by_id(req.season_id.0)
            .await?
            .series_id,
    );
    let cmd = CreateCharacter {
        id,
        season_id: req.season_id,
        series_id,
        name: req.name,
        category: req.category,
    };
    let (id, version) = state
        .ports
        .character_commands()
        .create(current_user.sub.clone(), cmd)
        .await?;
    Ok((StatusCode::CREATED, Json(IdVersionResponse { id, version })))
}

#[utoipa::path(
    get,
    path = "/characters/{id}",
    params(("id" = Uuid, Path, description = "Character id")),
    responses((status = 200, body = CharacterView), (status = 404, body = ProblemDetails))
)]
pub async fn get_character<P: Ports>(
    State(state): State<AppState<P>>,
    Path(id): Path<Uuid>,
) -> ApiResult<CharacterView> {
    let view = state.ports.character_repo().find_by_id(id).await?;
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
        .await?;
    Ok((StatusCode::OK, Json(views)))
}

#[utoipa::path(
    patch,
    path = "/characters/{id}/measurements",
    request_body = UpdateMeasurementsRequest,
    responses(
        (status = 200, body = AggregateVersion),
        (status = 404, body = ProblemDetails),
        (status = 409, body = ProblemDetails),
    )
)]
pub async fn update_measurements<P: Ports>(
    State(state): State<AppState<P>>,
    current_user: CurrentUser,
    Path(id): Path<Uuid>,
    Json(req): Json<UpdateMeasurementsRequest>,
) -> ApiResult<AggregateVersion> {
    let series_id = Some(series_id_for_character(&state, id).await?);
    let cmd = UpdateMeasurements {
        id,
        measurements: req.measurements,
        series_id,
        version: req.version,
    };
    let version = state
        .ports
        .character_commands()
        .update_measurements(current_user.sub.clone(), cmd)
        .await?;
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
    let series_id = Some(series_id_for_character(&state, id).await?);
    let cmd = UpdateContactInfo {
        id,
        contact_info: req.contact_info,
        series_id,
        version: req.version,
    };
    let version = state
        .ports
        .character_commands()
        .update_contact_info(current_user.sub.clone(), cmd)
        .await?;
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
        (status = 422, description = "Validation error", body = ProblemDetails),
    )
)]
pub async fn create_costume<P: Ports>(
    State(state): State<AppState<P>>,
    current_user: CurrentUser,
    Json(_req): Json<CreateCostumeRequest>,
) -> ApiResult<IdVersionResponse> {
    let id = Uuid::now_v7();
    // A fresh costume has no character association yet — the series is
    // genuinely unknown at creation (issue #147).
    let cmd = CreateCostume {
        id,
        series_id: None,
    };
    let (id, version) = state
        .ports
        .costume_commands()
        .create(current_user.sub.clone(), cmd)
        .await?;
    Ok((StatusCode::CREATED, Json(IdVersionResponse { id, version })))
}

#[utoipa::path(
    get,
    path = "/costumes/{id}",
    params(("id" = Uuid, Path, description = "Costume id")),
    responses((status = 200, body = CostumeView), (status = 404, body = ProblemDetails))
)]
pub async fn get_costume<P: Ports>(
    State(state): State<AppState<P>>,
    Path(id): Path<Uuid>,
) -> ApiResult<CostumeView> {
    let view = state.ports.costume_repo().find_by_id(id).await?;
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
        .await?;
    Ok((StatusCode::OK, Json(views)))
}

#[utoipa::path(
    patch,
    path = "/costumes/{id}/notes",
    request_body = UpdateCostumeNotesRequest,
    responses(
        (status = 200, body = AggregateVersion),
        (status = 404, body = ProblemDetails),
        (status = 409, body = ProblemDetails),
    )
)]
pub async fn update_costume_notes<P: Ports>(
    State(state): State<AppState<P>>,
    current_user: CurrentUser,
    Path(id): Path<Uuid>,
    Json(req): Json<UpdateCostumeNotesRequest>,
) -> ApiResult<AggregateVersion> {
    let series_id = series_id_for_costume(&state, id).await?;
    let cmd = UpdateCostumeNotes {
        id,
        notes: req.notes,
        series_id,
        version: req.version,
    };
    let version = state
        .ports
        .costume_commands()
        .update_notes(current_user.sub.clone(), cmd)
        .await?;
    Ok((StatusCode::OK, Json(version)))
}

#[utoipa::path(
    post,
    path = "/costumes/{id}/assign",
    request_body = AssignCostumeRequest,
    responses((status = 200, body = AggregateVersion), (status = 409, body = ProblemDetails)),
)]
pub async fn assign_costume<P: Ports>(
    State(state): State<AppState<P>>,
    current_user: CurrentUser,
    Path(id): Path<Uuid>,
    Json(req): Json<AssignCostumeRequest>,
) -> ApiResult<AggregateVersion> {
    let series_id = Some(series_id_for_character(&state, req.character_id).await?);
    let cmd = AssignCostumeToCharacter {
        id,
        character_id: req.character_id,
        series_id,
        version: req.version,
    };
    let version = state
        .ports
        .costume_commands()
        .assign_to_character(current_user.sub.clone(), cmd)
        .await?;
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
    let series_id = series_id_for_costume(&state, id).await?;
    let cmd = UnassignCostume {
        id,
        series_id,
        version: req.version,
    };
    let version = state
        .ports
        .costume_commands()
        .unassign(current_user.sub.clone(), cmd)
        .await?;
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
                series_id: series_id_for_costume(&state, id).await?,
                version: req.version,
            },
        )
        .await?;
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
    let series_id = Some(
        state
            .ports
            .season_repo()
            .find_by_id(season_id.0)
            .await?
            .series_id,
    );
    let cmd = CreateCostumeCategory {
        id,
        season_id,
        series_id,
        name: req.name,
        order_key: req.order_key,
    };
    let (id, version) = state
        .ports
        .costume_category_commands()
        .create(current_user.sub.clone(), cmd)
        .await?;
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
        .await?;
    Ok((StatusCode::OK, Json(views)))
}

#[utoipa::path(
    patch,
    path = "/costume-categories/{id}",
    params(("id" = Uuid, Path, description = "Costume category id")),
    request_body = UpdateCostumeCategoryRequest,
    responses(
        (status = 200, body = AggregateVersion),
        (status = 422, description = "No update field provided"),
        (status = 409, body = ProblemDetails),
    ),
)]
pub async fn update_costume_category<P: Ports>(
    State(state): State<AppState<P>>,
    current_user: CurrentUser,
    Path(id): Path<Uuid>,
    Json(req): Json<UpdateCostumeCategoryRequest>,
) -> ApiResult<AggregateVersion> {
    let actor = current_user.sub.clone();
    let series_id = Some(series_id_for_costume_category(&state, id).await?);
    let cmds = state.ports.costume_category_commands();
    if let Some(name) = req.name {
        let version = cmds
            .rename(
                actor.clone(),
                RenameCostumeCategory {
                    id,
                    name,
                    series_id,
                    version: req.version,
                },
            )
            .await?;
        return Ok((StatusCode::OK, Json(version)));
    }
    if let Some(order_key) = req.order_key {
        let version = cmds
            .reorder(
                actor,
                ReorderCostumeCategory {
                    id,
                    order_key,
                    series_id,
                    version: req.version,
                },
            )
            .await?;
        return Ok((StatusCode::OK, Json(version)));
    }
    Err(ApiError::Validation(
        "no update field provided (name or order_key)",
    ))
}

#[utoipa::path(
    post,
    path = "/costume-categories/{id}/archive",
    params(("id" = Uuid, Path, description = "Costume category id")),
    request_body = VersionRequest,
    responses((status = 200, body = AggregateVersion), (status = 409, body = ProblemDetails)),
)]
pub async fn archive_costume_category<P: Ports>(
    State(state): State<AppState<P>>,
    current_user: CurrentUser,
    Path(id): Path<Uuid>,
    Json(req): Json<VersionRequest>,
) -> ApiResult<AggregateVersion> {
    let series_id = Some(series_id_for_costume_category(&state, id).await?);
    let version = state
        .ports
        .costume_category_commands()
        .archive(
            current_user.sub.clone(),
            ArchiveCostumeCategory {
                id,
                series_id,
                version: req.version,
            },
        )
        .await?;
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
        (status = 400, body = ProblemDetails, description = "Invalid request (e.g., malformed user_id)"),
        (status = 403, body = ProblemDetails, description = "Caller is not an active member of the active block (X-Active-Block header)"),
        (status = 409, body = ProblemDetails, description = "Conflicting state (e.g., user is already a member)"),
    ),
)]
pub async fn invite_member<P: Ports>(
    State(state): State<AppState<P>>,
    current_user: CurrentUser,
    Path(id): Path<Uuid>,
    Json(req): Json<InviteMemberRequest>,
) -> ApiResult<()> {
    let series_id = state.ports.block_repo().find_by_id(id).await?.series_id;
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
        .await?;
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
        (status = 409, body = ProblemDetails, description = "No pending invitation for the caller in this block"),
        (status = 403, body = ProblemDetails, description = "Unauthorized"),
    ),
)]
pub async fn accept_invitation<P: Ports>(
    State(state): State<AppState<P>>,
    current_user: CurrentUser,
    Path(id): Path<Uuid>,
) -> ApiResult<()> {
    let series_id = state.ports.block_repo().find_by_id(id).await?.series_id;
    let cmd = AcceptInvitation {
        block_id: BlockId::from_uuid(id),
        series_id,
        user_id: current_user.sub.clone(),
    };
    state
        .ports
        .membership_commands()
        .accept_invitation(current_user.sub.clone(), cmd)
        .await?;
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
        (status = 422, body = ProblemDetails, description = "Validation error"),
        (status = 403, body = ProblemDetails, description = "Caller is not an active member of the active block"),
        (status = 404, body = ProblemDetails, description = "Target user is not a member of the block"),
    ),
)]
pub async fn grant_role<P: Ports>(
    State(state): State<AppState<P>>,
    current_user: CurrentUser,
    Path((id, user_id)): Path<(Uuid, String)>,
    Json(req): Json<GrantRoleRequest>,
) -> ApiResult<()> {
    let series_id = state.ports.block_repo().find_by_id(id).await?.series_id;
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
        .await?;
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
        (status = 422, body = ProblemDetails, description = "Validation error"),
        (status = 403, body = ProblemDetails, description = "Caller is not an active member of the active block"),
        (status = 404, body = ProblemDetails, description = "Target user is not a member of the block"),
    ),
)]
pub async fn remove_member<P: Ports>(
    State(state): State<AppState<P>>,
    current_user: CurrentUser,
    Path((id, user_id)): Path<(Uuid, String)>,
) -> ApiResult<()> {
    let series_id = state.ports.block_repo().find_by_id(id).await?.series_id;
    let cmd = RemoveMember {
        block_id: BlockId::from_uuid(id),
        series_id,
        user_id: UserId::from_sub(user_id),
    };
    state
        .ports
        .membership_commands()
        .remove_member(current_user.sub.clone(), cmd)
        .await?;
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
        (status = 422, body = ProblemDetails, description = "Validation error"),
        (status = 403, body = ProblemDetails, description = "Caller is not an active member of the active block"),
    ),
)]
pub async fn leave_block<P: Ports>(
    State(state): State<AppState<P>>,
    current_user: CurrentUser,
    Path(id): Path<Uuid>,
) -> ApiResult<()> {
    let series_id = state.ports.block_repo().find_by_id(id).await?.series_id;
    let cmd = LeaveBlock {
        block_id: BlockId::from_uuid(id),
        series_id,
    };
    state
        .ports
        .membership_commands()
        .leave_block(current_user.sub.clone(), cmd)
        .await?;
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
        (status = 400, body = ProblemDetails, description = "Missing or malformed X-Active-Block header"),
        (status = 403, body = ProblemDetails, description = "Caller is not an active member of the active block"),
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
        .await?;
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
        (status = 400, body = ProblemDetails, description = "Missing or malformed X-Active-Block header"),
        (status = 403, body = ProblemDetails, description = "Caller is not an active member of the active block"),
        (status = 404, body = ProblemDetails, description = "Membership not found"),
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
        .await?;
    match view {
        Some(v) => Ok((StatusCode::OK, Json(v))),
        None => Err(ApiError::Domain(DomainError::NotFound {
            code: &MEMBERSHIP_NOT_FOUND,
            resource: "membership",
            id: Uuid::nil(),
        })),
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
        (status = 422, body = ProblemDetails, description = "Validation error"),
        (status = 403, body = ProblemDetails, description = "Not authorized"),
        (status = 413, body = ProblemDetails, description = "Payload too large"),
        (status = 415, body = ProblemDetails, description = "Unsupported media type"),
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
            return Err(ApiError::UnsupportedMediaType(
                "HEIC/HEIF not supported. Convert to JPEG before upload.",
            ));
        }
        return Err(ApiError::UnsupportedMediaType(
            "unsupported photo content type; accepted: image/jpeg, image/png, image/webp",
        ));
    }

    // Enforce size cap.
    let max_size_mb: usize = std::env::var("PHOTO_MAX_SIZE_MB")
        .ok()
        .and_then(|v| v.parse().ok())
        .unwrap_or(20);
    let max_bytes = max_size_mb * 1024 * 1024;
    if body.len() > max_bytes {
        return Err(ApiError::PayloadTooLarge(
            "uploaded file exceeds the configured size limit",
        ));
    }

    // Fetch the costume to get its season_id for authorization.
    let costume = state.ports.costume_repo().find_by_id(costume_id).await?;

    // Resolve season_id from the costume's character.
    let season_id = match costume.character_id {
        Some(char_id) => {
            let character = state.ports.character_repo().find_by_id(char_id).await?;
            character.season_id
        }
        None => {
            return Err(ApiError::Validation(
                "costume has no assigned character — cannot determine season",
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
        return Err(ApiError::Forbidden(
            "not authorized to upload photos in this season",
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
        .await?;

    // Dispatch UploadPhoto command.
    let series_id = series_id_for_costume(&state, costume_id).await?;
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
                series_id,
            },
        )
        .await
        .inspect_err(|_| {
            // Compensating delete: best-effort, cannot await in sync closure.
            drop(state.ports.photo_storage().delete_all(photo_id));
        })?;

    // Dispatch LinkPhoto command on the costume aggregate.
    let series_id = series_id_for_costume(&state, costume_id).await?;
    let version = costume.version;
    state
        .ports
        .costume_commands()
        .link_photo(
            current_user.sub.clone(),
            LinkPhoto {
                id: costume_id,
                photo_id: photo_id.0,
                series_id,
                version,
            },
        )
        .await
        .inspect_err(|_| {
            // Compensating delete: best-effort, cannot await in sync closure.
            drop(state.ports.photo_storage().delete_all(photo_id));
        })?;

    // Read back the projected photo view.
    let view = state.ports.photo_repo().find_by_id(photo_id).await?;

    Ok((StatusCode::CREATED, Json(view)))
}

/// OpenAPI documentation type for the costume-photo byte response.
//
/// The handler returns `Vec<u8>`; utoipa would otherwise document that as
/// `array of integer`, which the OpenAPI generator turns into a
/// `BuiltList<int>` that the Dart client tries to JSON-deserialize — and the
/// response body is raw JPEG/PNG/WebP bytes, not JSON. Modeling the response
/// as `type: string, format: binary` makes the generator return the raw
/// bytes as `List<int>` without deserialization, which is what callers need.
/// utoipa 5 has no built-in `Vec<u8>` -> binary mapping, so the schema is
/// built by hand here.
#[allow(dead_code)]
struct CostumePhotoBytes;

impl utoipa::PartialSchema for CostumePhotoBytes {
    fn schema() -> utoipa::openapi::RefOr<utoipa::openapi::Schema> {
        utoipa::openapi::RefOr::T(utoipa::openapi::Schema::Object(
            utoipa::openapi::schema::ObjectBuilder::new()
                .schema_type(utoipa::openapi::schema::SchemaType::Type(
                    utoipa::openapi::schema::Type::String,
                ))
                .format(Some(utoipa::openapi::SchemaFormat::KnownFormat(
                    utoipa::openapi::KnownFormat::Binary,
                )))
                .description(Some("Raw costume photo variant bytes (JPEG/PNG/WebP)."))
                .build(),
        ))
    }
}

impl utoipa::ToSchema for CostumePhotoBytes {}

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
        (status = 200, description = "Photo bytes", body = inline(CostumePhotoBytes), content_type = "image/jpeg"),
        (status = 403, body = ProblemDetails, description = "Not authorized"),
        (status = 404, body = ProblemDetails, description = "Photo or costume not found"),
    ),
)]
pub async fn get_costume_photo_bytes<P: Ports>(
    State(state): State<AppState<P>>,
    current_user: CurrentUser,
    Path((costume_id, photo_id)): Path<(Uuid, Uuid)>,
    Query(query): Query<PhotoBytesQuery>,
) -> Result<(StatusCode, axum::http::HeaderMap, Vec<u8>), ApiError> {
    // Fetch the costume to get its season_id for authorization.
    let costume = state.ports.costume_repo().find_by_id(costume_id).await?;

    // Resolve season_id from the costume's character.
    let season_id = match costume.character_id {
        Some(char_id) => {
            let character = state.ports.character_repo().find_by_id(char_id).await?;
            character.season_id
        }
        None => {
            return Err(ApiError::Validation("costume has no assigned character"));
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
        return Err(ApiError::Forbidden(
            "not authorized to download photos in this season",
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
        .await?;

    // Build response headers for streaming.
    let mut headers = axum::http::HeaderMap::new();
    let content_type_header = photo_bytes
        .content_type
        .parse::<axum::http::HeaderValue>()
        .map_err(|e| {
            tracing::error!(error = %e, "invalid content-type in photo metadata");
            ApiError::Internal
        })?;
    headers.insert(axum::http::header::CONTENT_TYPE, content_type_header);
    let content_length_header = photo_bytes
        .size_bytes
        .to_string()
        .parse::<axum::http::HeaderValue>()
        .map_err(|e| {
            tracing::error!(error = %e, "invalid content-length in photo metadata");
            ApiError::Internal
        })?;
    headers.insert(axum::http::header::CONTENT_LENGTH, content_length_header);
    headers.insert(
        axum::http::header::CACHE_CONTROL,
        #[allow(clippy::expect_used)] // hardcoded safe header literal
        "private, max-age=300"
            .parse()
            .expect("hardcoded safe header value"),
    );
    if let Some(ref etag) = photo_bytes.etag {
        let etag_header = etag.parse::<axum::http::HeaderValue>().map_err(|e| {
            tracing::error!(error = %e, "invalid etag in photo metadata");
            ApiError::Internal
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
        (status = 403, body = ProblemDetails, description = "Not authorized"),
        (status = 404, body = ProblemDetails, description = "Costume not found"),
    ),
)]
pub async fn delete_costume_photo<P: Ports>(
    State(state): State<AppState<P>>,
    current_user: CurrentUser,
    Path((costume_id, photo_id)): Path<(Uuid, Uuid)>,
) -> ApiResult<()> {
    // Fetch the costume to get its season_id for authorization.
    let costume = state.ports.costume_repo().find_by_id(costume_id).await?;

    // Resolve season_id from the costume's character.
    let season_id = match costume.character_id {
        Some(char_id) => {
            let character = state.ports.character_repo().find_by_id(char_id).await?;
            character.season_id
        }
        None => {
            return Err(ApiError::Validation("costume has no assigned character"));
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
        return Err(ApiError::Forbidden(
            "not authorized to delete photos in this season",
        ));
    }

    // Dispatch UnlinkPhoto on the costume aggregate.
    let series_id = series_id_for_costume(&state, costume_id).await?;
    state
        .ports
        .costume_commands()
        .unlink_photo(
            current_user.sub.clone(),
            UnlinkPhoto {
                id: costume_id,
                photo_id,
                series_id,
                version: costume.version,
            },
        )
        .await?;

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
        return Err(ApiError::BadRequest(
            "shooting_day_id in body must match path parameter",
        ));
    }
    let id = SceneShootId::new();
    let series_id = Some(series_id_for_scene(&state, scene_id).await?);
    let cmd = PlanSceneShoot {
        id,
        scene_id,
        shooting_day_id: day_id,
        series_id,
        planned_order: req.planned_order,
    };
    let (id, version) = state
        .ports
        .scene_shoot_commands()
        .plan(current_user.sub.clone(), cmd)
        .await?;
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
    let series_id = Some(series_id_for_scene_shoot(&state, shoot_id).await?);
    let cmd = ReplanSceneShoot {
        id: shoot_id,
        planned_order: req.planned_order,
        series_id,
        version: req.version,
    };
    let version = state
        .ports
        .scene_shoot_commands()
        .replan(current_user.sub.clone(), cmd)
        .await?;
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
    let series_id = Some(series_id_for_scene_shoot(&state, shoot_id).await?);
    let cmd = StartSceneShoot {
        id: shoot_id,
        start_dt: req.resolve_start_dt(),
        series_id,
        version: req.version,
    };
    let version = state
        .ports
        .scene_shoot_commands()
        .start(current_user.sub.clone(), cmd)
        .await?;
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
    let series_id = Some(series_id_for_scene_shoot(&state, shoot_id).await?);
    let cmd = SetActualOrder {
        id: shoot_id,
        actual_order: req.actual_order,
        series_id,
        version: req.version,
    };
    let version = state
        .ports
        .scene_shoot_commands()
        .set_actual_order(current_user.sub.clone(), cmd)
        .await?;
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
    let series_id = Some(series_id_for_scene_shoot(&state, shoot_id).await?);
    let cmd = FinishSceneShoot {
        id: shoot_id,
        end_dt: req.resolve_end_dt(),
        series_id,
        version: req.version,
    };
    let version = state
        .ports
        .scene_shoot_commands()
        .finish(current_user.sub.clone(), cmd)
        .await?;
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
    let series_id = Some(series_id_for_scene_shoot(&state, shoot_id).await?);
    let cmd = SkipSceneShoot {
        id: shoot_id,
        series_id,
        version: req.version,
    };
    let version = state
        .ports
        .scene_shoot_commands()
        .skip(current_user.sub.clone(), cmd)
        .await?;
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
    let view = state.ports.scene_shoot_repo().find_by_id(shoot_id).await?;
    Ok((StatusCode::OK, Json(view)))
}

#[utoipa::path(
    get,
    path = "/shooting-days/{day_id}/scenes/{scene_id}/scene-shoots",
    params(
        ("day_id" = ShootingDayId, Path, description = "Shooting day id"),
        ("scene_id" = Uuid, Path, description = "Scene id"),
    ),
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
        .await?;
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
    let series_id = Some(series_id_for_scene_shoot(&state, shoot_id).await?);
    let cmd = AddSceneShootNote {
        id: shoot_id,
        note_id,
        body: req.body,
        series_id,
        author: None,
    };
    let version = state
        .ports
        .scene_shoot_commands()
        .add_note(current_user.sub.clone(), cmd)
        .await?;
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
    let series_id = Some(series_id_for_scene_shoot(&state, shoot_id).await?);
    let cmd = UpdateSceneShootNote {
        id: shoot_id,
        note_id,
        body: req.body,
        series_id,
        version: req.version,
    };
    let version = state
        .ports
        .scene_shoot_commands()
        .update_note(current_user.sub.clone(), cmd)
        .await?;
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
    let series_id = Some(series_id_for_scene_shoot(&state, shoot_id).await?);
    let cmd = RemoveSceneShootNote {
        id: shoot_id,
        note_id,
        series_id,
        version: req.version,
    };
    let version = state
        .ports
        .scene_shoot_commands()
        .remove_note(current_user.sub.clone(), cmd)
        .await?;
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
    let shooting_day = state.ports.shooting_day_repo().find_by_id(day_id).await?;
    let episode = state
        .ports
        .episode_repo()
        .find_by_id(shooting_day.episode_id.0)
        .await?;
    let block = state
        .ports
        .block_repo()
        .find_by_id(episode.block_id.0)
        .await?;
    // block.season_id is a SeasonId — extract inner Uuid
    let season_id = block.season_id;

    let is_authorized = state
        .ports
        .membership_repo()
        .has_active_costume_role_in_season(season_id, current_user.sub.clone())
        .await
        .unwrap_or(false);
    if !is_authorized {
        return Err(ApiError::Forbidden(
            "not authorized to link continuity photos",
        ));
    }

    let series_id = Some(block.series_id);
    let cmd = LinkContinuityPhoto {
        id: shoot_id,
        photo_id: req.photo_id,
        series_id,
        version: req.version,
    };
    let version = state
        .ports
        .scene_shoot_commands()
        .link_continuity_photo(current_user.sub.clone(), cmd)
        .await?;
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
    let view = state.ports.scene_shoot_repo().find_by_id(shoot_id).await?;
    Ok((StatusCode::OK, Json(view.continuity_photo_ids)))
}

#[utoipa::path(
    delete,
    path = "/shooting-days/{day_id}/scenes/{scene_id}/scene-shoots/{shoot_id}/continuity-photos/{photo_id}",
    params(VersionRequest),
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
    let shooting_day = state.ports.shooting_day_repo().find_by_id(day_id).await?;
    let episode = state
        .ports
        .episode_repo()
        .find_by_id(shooting_day.episode_id.0)
        .await?;
    let block = state
        .ports
        .block_repo()
        .find_by_id(episode.block_id.0)
        .await?;
    let season_id = block.season_id;

    let is_authorized = state
        .ports
        .membership_repo()
        .has_active_costume_role_in_season(season_id, current_user.sub.clone())
        .await
        .unwrap_or(false);
    if !is_authorized {
        return Err(ApiError::Forbidden(
            "not authorized to unlink continuity photos",
        ));
    }

    let series_id = Some(block.series_id);
    let cmd = UnlinkContinuityPhoto {
        id: shoot_id,
        photo_id,
        series_id,
        version: version_req.version,
    };
    let version = state
        .ports
        .scene_shoot_commands()
        .unlink_continuity_photo(current_user.sub.clone(), cmd)
        .await?;
    Ok((StatusCode::OK, Json(version)))
}

// ---------------------------------------------------------------------------
// ShootingDay wrap handler
// ---------------------------------------------------------------------------

#[utoipa::path(
    post,
    path = "/shooting-days/{id}/wrap",
    params(("id" = ShootingDayId, Path, description = "Shooting day id")),
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
    let series_id = Some(series_id_for_shooting_day(&state, id).await?);
    let cmd = WrapShootingDay {
        id,
        series_id,
        version: req.version,
    };
    let version = state
        .ports
        .shooting_day_commands()
        .wrap(current_user.sub.clone(), cmd)
        .await?;
    Ok((StatusCode::OK, Json(version)))
}

// ---------------------------------------------------------------------------
// Report handlers
// ---------------------------------------------------------------------------

#[utoipa::path(
    get,
    path = "/shooting-days/{id}/report/dispo",
    params(("id" = ShootingDayId, Path, description = "Shooting day id")),
    responses((status = 200, body = Vec<DispoRow>)),
)]
pub async fn dispo_report<P: Ports>(
    State(state): State<AppState<P>>,
    current_user: CurrentUser,
    Path(id): Path<ShootingDayId>,
) -> ApiResult<Vec<DispoRow>> {
    // AUTHZ-GATE: handler-internal auth gate
    let shooting_day = state.ports.shooting_day_repo().find_by_id(id).await?;
    let episode = state
        .ports
        .episode_repo()
        .find_by_id(shooting_day.episode_id.0)
        .await?;
    let block = state
        .ports
        .block_repo()
        .find_by_id(episode.block_id.0)
        .await?;
    let is_authorized = state
        .ports
        .membership_repo()
        .has_active_costume_role_in_season(block.season_id, current_user.sub.clone())
        .await
        .unwrap_or(false);
    if !is_authorized {
        return Err(ApiError::Forbidden("not authorized to view reports"));
    }

    let rows = state
        .ports
        .scene_shoot_report_repo()
        .dispo_report(id)
        .await?;
    Ok((StatusCode::OK, Json(rows)))
}

#[utoipa::path(
    get,
    path = "/shooting-days/{id}/report/shoot-day",
    params(("id" = ShootingDayId, Path, description = "Shooting day id")),
    responses((status = 200, body = Vec<ShootDayRow>)),
)]
pub async fn shoot_day_report<P: Ports>(
    State(state): State<AppState<P>>,
    current_user: CurrentUser,
    Path(id): Path<ShootingDayId>,
) -> ApiResult<Vec<ShootDayRow>> {
    // AUTHZ-GATE: handler-internal auth gate
    let shooting_day = state.ports.shooting_day_repo().find_by_id(id).await?;
    let episode = state
        .ports
        .episode_repo()
        .find_by_id(shooting_day.episode_id.0)
        .await?;
    let block = state
        .ports
        .block_repo()
        .find_by_id(episode.block_id.0)
        .await?;
    let is_authorized = state
        .ports
        .membership_repo()
        .has_active_costume_role_in_season(block.season_id, current_user.sub.clone())
        .await
        .unwrap_or(false);
    if !is_authorized {
        return Err(ApiError::Forbidden("not authorized to view reports"));
    }

    let rows = state
        .ports
        .scene_shoot_report_repo()
        .shoot_day_report(id)
        .await?;
    Ok((StatusCode::OK, Json(rows)))
}

#[utoipa::path(
    get,
    path = "/shooting-days/{id}/report/soll-ist",
    params(("id" = ShootingDayId, Path, description = "Shooting day id")),
    responses((status = 200, body = SollIstReport)),
)]
pub async fn soll_ist_report<P: Ports>(
    State(state): State<AppState<P>>,
    current_user: CurrentUser,
    Path(id): Path<ShootingDayId>,
) -> ApiResult<SollIstReport> {
    // AUTHZ-GATE: handler-internal auth gate
    let shooting_day = state.ports.shooting_day_repo().find_by_id(id).await?;
    let episode = state
        .ports
        .episode_repo()
        .find_by_id(shooting_day.episode_id.0)
        .await?;
    let block = state
        .ports
        .block_repo()
        .find_by_id(episode.block_id.0)
        .await?;
    let is_authorized = state
        .ports
        .membership_repo()
        .has_active_costume_role_in_season(block.season_id, current_user.sub.clone())
        .await
        .unwrap_or(false);
    if !is_authorized {
        return Err(ApiError::Forbidden("not authorized to view reports"));
    }

    let report = state
        .ports
        .scene_shoot_report_repo()
        .soll_ist_report(id)
        .await?;
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

/// Map a `ReportRenderError` to an `ApiError` (ADR-031).
///
/// The status/code mapping (422 limits, 408 timeout, 500 otherwise) lives in
/// `crate::problems::report_render_problem`; per-code registry entries land
/// in Tranche 2.
#[allow(dead_code)]
pub fn map_render_error(err: breakdown_core::reporting::ReportRenderError) -> ApiError {
    ApiError::ReportRender(err)
}

#[utoipa::path(
    get,
    path = "/shooting-days/{id}/report/dispo.pdf",
    params(("id" = ShootingDayId, Path, description = "Shooting day id")),
    responses((status = 200, description = "PDF report")),
)]
pub async fn dispo_report_pdf<P: Ports>(
    State(state): State<AppState<P>>,
    current_user: CurrentUser,
    Path(id): Path<ShootingDayId>,
) -> Result<(StatusCode, HeaderMap, Vec<u8>), ApiError> {
    // AUTHZ-GATE: handler-internal auth gate
    let shooting_day = state.ports.shooting_day_repo().find_by_id(id).await?;
    let episode = state
        .ports
        .episode_repo()
        .find_by_id(shooting_day.episode_id.0)
        .await?;
    let block = state
        .ports
        .block_repo()
        .find_by_id(episode.block_id.0)
        .await?;
    let is_authorized = state
        .ports
        .membership_repo()
        .has_active_costume_role_in_season(block.season_id, current_user.sub.clone())
        .await
        .unwrap_or(false);
    if !is_authorized {
        return Err(ApiError::Forbidden("not authorized to view reports"));
    }

    // Query report data
    let rows = state
        .ports
        .scene_shoot_report_repo()
        .dispo_report(id)
        .await?;

    // Render PDF via shared renderer
    let req = ReportRenderRequest {
        kind: ReportKind::Dispo,
        context: RenderPresentationContext {
            locale: ReportLocale::de_de(),
            timezone: "Europe/Berlin".into(),
            template_version: TEMPLATE_VERSION.to_string(),
        },
        data: serde_json::to_value(rows).map_err(|e| {
            tracing::error!(error = %e, "report serialization failed");
            ApiError::Internal
        })?,
    };
    let renderer = state.ports.report_renderer_ref();
    let rendered = renderer.render(req).await.map_err(map_render_error)?;

    let mut headers = HeaderMap::new();
    let content_type_value = rendered
        .content_type
        .parse::<axum::http::HeaderValue>()
        .map_err(|e| {
            tracing::error!(error = %e, "renderer produced invalid content-type");
            ApiError::Internal
        })?;
    headers.insert(axum::http::header::CONTENT_TYPE, content_type_value);
    let disposition_format = format!(
        r#"inline; filename="{}""#,
        sanitize_pdf_filename("dispo", "de-DE")
    );
    let disposition_value = disposition_format
        .parse::<axum::http::HeaderValue>()
        .map_err(|_| {
            tracing::error!("failed to construct Content-Disposition header");
            ApiError::Internal
        })?;
    headers.insert(axum::http::header::CONTENT_DISPOSITION, disposition_value);
    Ok((StatusCode::OK, headers, rendered.pdf_bytes))
}

#[utoipa::path(
    get,
    path = "/shooting-days/{id}/report/shoot-day.pdf",
    params(("id" = ShootingDayId, Path, description = "Shooting day id")),
    responses((status = 200, description = "PDF report")),
)]
pub async fn shoot_day_report_pdf<P: Ports>(
    State(state): State<AppState<P>>,
    current_user: CurrentUser,
    Path(id): Path<ShootingDayId>,
) -> Result<(StatusCode, HeaderMap, Vec<u8>), ApiError> {
    // AUTHZ-GATE: handler-internal auth gate
    let shooting_day = state.ports.shooting_day_repo().find_by_id(id).await?;
    let episode = state
        .ports
        .episode_repo()
        .find_by_id(shooting_day.episode_id.0)
        .await?;
    let block = state
        .ports
        .block_repo()
        .find_by_id(episode.block_id.0)
        .await?;
    let is_authorized = state
        .ports
        .membership_repo()
        .has_active_costume_role_in_season(block.season_id, current_user.sub.clone())
        .await
        .unwrap_or(false);
    if !is_authorized {
        return Err(ApiError::Forbidden("not authorized to view reports"));
    }

    // Query report data
    let rows = state
        .ports
        .scene_shoot_report_repo()
        .shoot_day_report(id)
        .await?;

    // Render PDF via shared renderer
    let req = ReportRenderRequest {
        kind: ReportKind::ShootDay,
        context: RenderPresentationContext {
            locale: ReportLocale::de_de(),
            timezone: "Europe/Berlin".into(),
            template_version: TEMPLATE_VERSION.to_string(),
        },
        data: serde_json::to_value(rows).map_err(|e| {
            tracing::error!(error = %e, "report serialization failed");
            ApiError::Internal
        })?,
    };
    let renderer = state.ports.report_renderer_ref();
    let rendered = renderer.render(req).await.map_err(map_render_error)?;

    let mut headers = HeaderMap::new();
    let content_type_value = rendered
        .content_type
        .parse::<axum::http::HeaderValue>()
        .map_err(|e| {
            tracing::error!(error = %e, "renderer produced invalid content-type");
            ApiError::Internal
        })?;
    headers.insert(axum::http::header::CONTENT_TYPE, content_type_value);
    let disposition_format = format!(
        r#"inline; filename="{}""#,
        sanitize_pdf_filename("shoot-day", "de-DE")
    );
    let disposition_value = disposition_format
        .parse::<axum::http::HeaderValue>()
        .map_err(|_| {
            tracing::error!("failed to construct Content-Disposition header");
            ApiError::Internal
        })?;
    headers.insert(axum::http::header::CONTENT_DISPOSITION, disposition_value);
    Ok((StatusCode::OK, headers, rendered.pdf_bytes))
}

#[utoipa::path(
    get,
    path = "/shooting-days/{id}/report/planned-vs-actual.pdf",
    params(("id" = ShootingDayId, Path, description = "Shooting day id")),
    responses((status = 200, description = "PDF report")),
)]
pub async fn planned_vs_actual_report_pdf<P: Ports>(
    State(state): State<AppState<P>>,
    current_user: CurrentUser,
    Path(id): Path<ShootingDayId>,
) -> Result<(StatusCode, HeaderMap, Vec<u8>), ApiError> {
    // AUTHZ-GATE: handler-internal auth gate
    let shooting_day = state.ports.shooting_day_repo().find_by_id(id).await?;
    let episode = state
        .ports
        .episode_repo()
        .find_by_id(shooting_day.episode_id.0)
        .await?;
    let block = state
        .ports
        .block_repo()
        .find_by_id(episode.block_id.0)
        .await?;
    let is_authorized = state
        .ports
        .membership_repo()
        .has_active_costume_role_in_season(block.season_id, current_user.sub.clone())
        .await
        .unwrap_or(false);
    if !is_authorized {
        return Err(ApiError::Forbidden("not authorized to view reports"));
    }

    // Query report data
    let report = state
        .ports
        .scene_shoot_report_repo()
        .soll_ist_report(id)
        .await?;

    // Render PDF via shared renderer
    let req = ReportRenderRequest {
        kind: ReportKind::PlannedVsActual,
        context: RenderPresentationContext {
            locale: ReportLocale::de_de(),
            timezone: "Europe/Berlin".into(),
            template_version: TEMPLATE_VERSION.to_string(),
        },
        data: serde_json::to_value(report).map_err(|e| {
            tracing::error!(error = %e, "report serialization failed");
            ApiError::Internal
        })?,
    };
    let renderer = state.ports.report_renderer_ref();
    let rendered = renderer.render(req).await.map_err(map_render_error)?;

    let mut headers = HeaderMap::new();
    let content_type_value = rendered
        .content_type
        .parse::<axum::http::HeaderValue>()
        .map_err(|e| {
            tracing::error!(error = %e, "renderer produced invalid content-type");
            ApiError::Internal
        })?;
    headers.insert(axum::http::header::CONTENT_TYPE, content_type_value);
    let disposition_format = format!(
        r#"inline; filename="{}""#,
        sanitize_pdf_filename("planned-vs-actual", "de-DE")
    );
    let disposition_value = disposition_format
        .parse::<axum::http::HeaderValue>()
        .map_err(|_| {
            tracing::error!("failed to construct Content-Disposition header");
            ApiError::Internal
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
    params(("id" = ShootingDayId, Path, description = "Shooting day id")),
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
) -> ApiResult<ManualArchiveResponse> {
    // Resolve shooting day → episode → block → season (fail closed).
    let shooting_day = state.ports.shooting_day_repo().find_by_id(id).await?;
    let episode = state
        .ports
        .episode_repo()
        .find_by_id(shooting_day.episode_id.0)
        .await?;
    let block = state
        .ports
        .block_repo()
        .find_by_id(episode.block_id.0)
        .await?;

    // AUTHZ-GATE: manual archive — CostumeDesigner + WardrobeSupervisor only
    // (stricter than PDF routes; CostumeAssistant is excluded). Fail closed.
    let is_authorized = state
        .ports
        .membership_repo()
        .has_active_report_archive_role_in_season(block.season_id, current_user.sub.clone())
        .await
        .unwrap_or(false);
    if !is_authorized {
        return Err(ApiError::Forbidden(
            "not authorized to enqueue report archival",
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
                tracing::error!(error = %e, "failed to enqueue manual report archival job");
                ApiError::Internal
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

#[utoipa::path(
    post,
    path = "/settings/gdrive",
    request_body = GDriveCredentialRequest,
    responses(
        (status = 201, description = "GDrive credential reference created", body = IdVersionResponse),
        (status = 400, description = "Invalid GDrive credential bundle", body = ProblemDetails),
        (status = 403, description = "Credential management forbidden", body = ProblemDetails),
        (status = 503, description = "Vault unavailable", body = ProblemDetails)
    )
)]
pub async fn create_gdrive_credential<P: Ports>(
    State(state): State<AppState<P>>,
    current_user: CurrentUser,
    Json(req): Json<GDriveCredentialRequest>,
) -> ApiResult<IdVersionResponse> {
    // AUTHZ-GATE: only active CostumeDesigner/CostumeAssistant members may
    // create GDrive credentials. The bundle is handed to Vault immediately.
    let authorized = state
        .ports
        .membership_repo()
        .has_active_credential_role(current_user.sub.clone())
        .await
        .unwrap_or(false);
    if !authorized {
        return Err(ApiError::Forbidden(
            "not authorized to manage external credentials",
        ));
    }
    let id = Uuid::now_v7();
    let bundle = req.into_bundle()?;
    let binding = state
        .ports
        .credential_vault()
        .store_gdrive(id, bundle)
        .await?;
    let cmd = CreateCredentialBinding {
        id,
        provider: "gdrive".into(),
        vault_key_id: binding.vault_key_id.clone(),
        vault_version: binding.vault_version,
    };
    match state
        .ports
        .settings_commands()
        .create(current_user.sub.clone(), cmd)
        .await
    {
        Ok((id, version)) => Ok((StatusCode::CREATED, Json(IdVersionResponse { id, version }))),
        Err(err) => {
            if let Err(destroy_err) = state
                .ports
                .credential_vault()
                .destroy(id, &binding.vault_key_id)
                .await
            {
                tracing::error!(
                    vault_key_id = %binding.vault_key_id,
                    error = %destroy_err,
                    "failed to compensate GDrive Vault write"
                );
            }
            Err(ApiError::from(err))
        }
    }
}

#[utoipa::path(
    patch,
    path = "/settings/{id}/gdrive",
    request_body = GDriveCredentialUpdateRequest,
    params(("id" = Uuid, Path, description = "Settings id")),
    responses(
        (status = 200, description = "GDrive credential reference rotated", body = IdVersionResponse),
        (status = 400, description = "Invalid GDrive credential bundle", body = ProblemDetails),
        (status = 403, description = "Credential management forbidden", body = ProblemDetails),
        (status = 404, body = ProblemDetails),
        (status = 409, description = "GDrive binding cannot be rotated", body = ProblemDetails),
        (status = 503, description = "Vault unavailable", body = ProblemDetails)
    )
)]
pub async fn rotate_gdrive_credential<P: Ports>(
    State(state): State<AppState<P>>,
    current_user: CurrentUser,
    Path(id): Path<Uuid>,
    Json(req): Json<GDriveCredentialUpdateRequest>,
) -> ApiResult<IdVersionResponse> {
    // AUTHZ-GATE: only active CostumeDesigner/CostumeAssistant members may
    // rotate GDrive credentials.
    let authorized = state
        .ports
        .membership_repo()
        .has_active_credential_role(current_user.sub.clone())
        .await
        .unwrap_or(false);
    if !authorized {
        return Err(ApiError::Forbidden(
            "not authorized to manage external credentials",
        ));
    }
    let view = state.ports.settings_repo().find_by_id(id).await?;
    if view.provider != "gdrive"
        || view.binding_state == breakdown_core::settings::views::CredentialBindingState::Revoked
    {
        return Err(ApiError::Conflict(
            "non-revoked GDrive credential binding required",
        ));
    }
    let bundle = req.bundle.into_bundle()?;
    let binding = state
        .ports
        .credential_vault()
        .store_gdrive(id, bundle)
        .await?;
    let binding_ref = breakdown_core::settings::ports::VaultBinding {
        vault_key_id: binding.vault_key_id.clone(),
        vault_version: binding.vault_version,
    };
    // Validate construction of the new provider adapter before replacing the
    // reference. If Vault/provider validation fails, the old binding remains
    // untouched and the candidate binding is compensated below.
    if let Err(error) = infra::reporting::OpenDalReportArchiveStorage::validate_from_vault(
        state.ports.credential_vault(),
        id,
        &binding_ref,
    )
    .await
    {
        tracing::error!(error = %error, "candidate GDrive binding failed provider validation");
        if let Err(destroy_err) = state
            .ports
            .credential_vault()
            .destroy(id, &binding.vault_key_id)
            .await
        {
            tracing::error!(
                vault_key_id = %binding.vault_key_id,
                error = %destroy_err,
                "failed to compensate unvalidated GDrive Vault binding"
            );
        }
        return Err(ApiError::ServiceUnavailable(
            "credential provider is temporarily unavailable",
        ));
    }
    let cmd = RotateCredentialBinding {
        id,
        provider: "gdrive".into(),
        vault_key_id: binding.vault_key_id.clone(),
        vault_version: binding.vault_version,
        version: req.version,
    };
    match state
        .ports
        .settings_commands()
        .rotate(current_user.sub.clone(), cmd)
        .await
    {
        Ok(version) => {
            // The new binding is now referenceable. Destroying the old key is
            // best-effort and happens only after the reference event succeeds.
            if let Err(err) = state
                .ports
                .credential_vault()
                .destroy(id, &view.vault_key_id)
                .await
            {
                tracing::error!(
                    vault_key_id = %view.vault_key_id,
                    error = %err,
                    "failed to destroy superseded GDrive Vault binding"
                );
            }
            Ok((StatusCode::OK, Json(IdVersionResponse { id, version })))
        }
        Err(err) => {
            if let Err(destroy_err) = state
                .ports
                .credential_vault()
                .destroy(id, &binding.vault_key_id)
                .await
            {
                tracing::error!(
                    vault_key_id = %binding.vault_key_id,
                    error = %destroy_err,
                    "failed to compensate rotated GDrive Vault binding"
                );
            }
            Err(ApiError::from(err))
        }
    }
}

#[derive(Deserialize, ToSchema)]
pub struct GDriveCredentialUpdateRequest {
    #[serde(flatten)]
    pub bundle: GDriveCredentialRequest,
    pub version: AggregateVersion,
}

#[utoipa::path(
    post,
    path = "/settings/credentials",
    request_body = CreateCredentialRequest,
    responses(
        (status = 201, description = "Credential reference created", body = IdVersionResponse),
        (status = 503, description = "Vault unavailable", body = ProblemDetails)
    )
)]
pub async fn create_credential<P: Ports>(
    State(state): State<AppState<P>>,
    current_user: CurrentUser,
    Json(req): Json<CreateCredentialRequest>,
) -> ApiResult<IdVersionResponse> {
    // AUTHZ-GATE: only active CostumeDesigner/CostumeAssistant members may
    // create external credentials (role-specific settings authz, ADR-027).
    let authorized = state
        .ports
        .membership_repo()
        .has_active_credential_role(current_user.sub.clone())
        .await
        .unwrap_or(false);
    if !authorized {
        return Err(ApiError::Forbidden(
            "not authorized to manage external credentials",
        ));
    }
    if req.provider.trim().is_empty() {
        return Err(ApiError::Validation("provider must not be empty"));
    }
    let id = Uuid::now_v7();
    let binding = state
        .ports
        .credential_vault()
        .store(id, &req.provider, SecretValue::new(req.secret))
        .await?;
    let cmd = CreateCredentialBinding {
        id,
        provider: req.provider,
        vault_key_id: binding.vault_key_id.clone(),
        vault_version: binding.vault_version,
    };
    match state
        .ports
        .settings_commands()
        .create(current_user.sub.clone(), cmd)
        .await
    {
        Ok((id, version)) => Ok((StatusCode::CREATED, Json(IdVersionResponse { id, version }))),
        Err(err) => {
            // Compensate the Vault write if event persistence failed. The
            // error response remains the command error; the secret is never
            // included in it.
            if let Err(destroy_err) = state
                .ports
                .credential_vault()
                .destroy(id, &binding.vault_key_id)
                .await
            {
                tracing::error!(
                    vault_key_id = %binding.vault_key_id,
                    error = %destroy_err,
                    "failed to compensate Vault write after command persistence failure"
                );
            }
            Err(ApiError::from(err))
        }
    }
}

#[utoipa::path(
    get,
    path = "/settings/{id}",
    params(("id" = Uuid, Path, description = "Settings id")),
    responses((status = 200, body = SettingsView), (status = 404, body = ProblemDetails))
)]
pub async fn get_settings<P: Ports>(
    State(state): State<AppState<P>>,
    _current_user: CurrentUser,
    Path(id): Path<Uuid>,
) -> ApiResult<SettingsView> {
    // AUTHZ-GATE: only active CostumeDesigner/CostumeAssistant members may
    // read external credential binding metadata (never the secret).
    let authorized = state
        .ports
        .membership_repo()
        .has_active_credential_role(_current_user.sub.clone())
        .await
        .unwrap_or(false);
    if !authorized {
        return Err(ApiError::Forbidden(
            "not authorized to manage external credentials",
        ));
    }
    let mut view = state.ports.settings_repo().find_by_id(id).await?;
    if view.binding_state == breakdown_core::settings::views::CredentialBindingState::Active
        && state.ports.credential_vault().check().await.is_err()
    {
        view.binding_state = breakdown_core::settings::views::CredentialBindingState::Unreachable;
    }
    Ok((StatusCode::OK, Json(view)))
}

#[utoipa::path(
    delete,
    path = "/settings/{id}",
    params(("id" = Uuid, Path, description = "Settings id")),
    request_body = VersionRequest,
    responses((status = 200, body = AggregateVersion), (status = 503, body = ProblemDetails))
)]
pub async fn revoke_settings<P: Ports>(
    State(state): State<AppState<P>>,
    current_user: CurrentUser,
    Path(id): Path<Uuid>,
    Json(req): Json<VersionRequest>,
) -> ApiResult<AggregateVersion> {
    // AUTHZ-GATE: only active CostumeDesigner/CostumeAssistant members may
    // revoke external credentials; Vault destruction happens after this gate.
    let authorized = state
        .ports
        .membership_repo()
        .has_active_credential_role(current_user.sub.clone())
        .await
        .unwrap_or(false);
    if !authorized {
        return Err(ApiError::Forbidden(
            "not authorized to manage external credentials",
        ));
    }
    let view = state.ports.settings_repo().find_by_id(id).await?;
    let version = state
        .ports
        .settings_commands()
        .revoke(
            current_user.sub,
            RevokeCredential {
                id,
                version: req.version,
            },
        )
        .await?;
    // The binding is now revoked in the aggregate. Destroy the Vault secret
    // best-effort; cleanup failure must not undo the successful revocation.
    if let Err(err) = state
        .ports
        .credential_vault()
        .destroy(id, &view.vault_key_id)
        .await
    {
        tracing::error!(
            vault_key_id = %view.vault_key_id,
            error = %err,
            "failed to destroy revoked credential secret in Vault"
        );
    }
    Ok((StatusCode::OK, Json(version)))
}

async fn authorize_ai_block<P: Ports>(
    state: &AppState<P>,
    current_user: &CurrentUser,
    headers: &HeaderMap,
) -> Result<BlockId, ApiError> {
    let raw = headers
        .get("x-active-block")
        .and_then(|value| value.to_str().ok())
        .ok_or(ApiError::BadRequest(
            "X-Active-Block header is required for AI import",
        ))?;
    let uuid =
        Uuid::parse_str(raw).map_err(|_| ApiError::BadRequest("invalid X-Active-Block header"))?;
    let block_id = BlockId::from_uuid(uuid);
    let block = state.ports.block_repo().find_by_id(uuid).await?;
    // AUTHZ-GATE: block-scoped AI import (script/schedule upload, apply)
    // requires active costume-dept membership in the block's season — decided
    // via the (fallible) season policy so read-model failures surface as
    // mapped errors, not as a silent 403.
    let decision = state
        .authorization_policy
        .authorize_season_result(&SeasonAuthContext {
            actor: current_user.sub.clone(),
            season_id: block.season_id,
            action: Action::Write,
        })
        .await?;
    if decision != PolicyDecision::Allow {
        return Err(ApiError::Forbidden(
            "not authorized for this production block",
        ));
    }
    Ok(block_id)
}

async fn authorize_ai_job<P: Ports>(
    state: &AppState<P>,
    current_user: &CurrentUser,
    job: &breakdown_core::ai::AiImportJob,
    action: Action,
) -> Result<(), ApiError> {
    if job.user_id != current_user.sub {
        return Err(forbidden_ai_config());
    }
    if let Some(block_id) = job.block_id {
        let block = state.ports.block_repo().find_by_id(block_id.0).await?;
        // AUTHZ-GATE: AI job status/preview/apply is privileged — the caller
        // must hold an active costume-dept role in the job's season, decided
        // via the (fallible) season policy.
        let decision = state
            .authorization_policy
            .authorize_season_result(&SeasonAuthContext {
                actor: current_user.sub.clone(),
                season_id: block.season_id,
                action,
            })
            .await?;
        if decision != PolicyDecision::Allow {
            return Err(forbidden_ai_config());
        }
    }
    Ok(())
}

fn digest_hex(body: &[u8]) -> String {
    let digest = Sha256::digest(body);
    digest.iter().map(|byte| format!("{byte:02x}")).collect()
}

fn ai_dedup_key(
    user_id: &UserId,
    kind: DocumentKind,
    format: SourceFormat,
    digest: &str,
) -> String {
    // The declared format is part of the identity: identical bytes declared
    // as CSV vs. PDF/plain-text route to different extraction paths, so a
    // re-upload with a different Content-Type must enqueue a distinct job
    // (issue #221).
    format!(
        "{}|{}|{}|{digest}",
        user_id.as_str(),
        kind.as_str(),
        format.as_str()
    )
}

async fn enqueue_ai_upload<P: Ports>(
    state: &AppState<P>,
    current_user: CurrentUser,
    headers: HeaderMap,
    body: Bytes,
    kind: DocumentKind,
) -> ApiResult<AiImportJobId> {
    if !state.ai_import_enabled {
        return Err(ApiError::NotFound("AI import is disabled"));
    }
    // Capture the declared document format from the upload's Content-Type so
    // the worker can route CSV natively and PDF/plain-text through the LLM
    // extraction path (issue #221). The callers gate the content type before
    // reaching this helper; a format that slips through is rejected rather
    // than defaulted, so a mislabelled upload cannot silently take the wrong
    // extraction path.
    let source_format = match request_content_type(&headers).as_str() {
        "text/csv" => SourceFormat::Csv,
        "application/pdf" => SourceFormat::Pdf,
        "text/plain" => SourceFormat::PlainText,
        other => {
            tracing::warn!(content_type = %other, "unsupported AI import content type");
            return Err(ApiError::UnsupportedMediaType(
                "unsupported AI import content type; expected text/csv, application/pdf or text/plain",
            ));
        }
    };
    let block_id = authorize_ai_block(state, &current_user, &headers).await?;
    // Use the bound resolved once into AppState (shared with the extractor
    // limit in `routes()`); no per-request environment reads.
    if body.len() as u64 > state.ai_import_max_document_bytes {
        return Err(ApiError::PayloadTooLarge(
            "AI import document exceeds the configured size limit",
        ));
    }
    let digest = digest_hex(&body);
    let job_id = AiImportJobId::new();
    let source_handle = state
        .ports
        .ai_document_store()
        .put_source(job_id, body.to_vec())
        .await?;
    let result = state
        .ports
        .ai_import_queue()
        .enqueue(AiImportEnqueueRequest {
            id: job_id,
            user_id: current_user.sub.clone(),
            document_kind: kind,
            source_format,
            block_id: Some(block_id),
            dedup_key: ai_dedup_key(&current_user.sub, kind, source_format, &digest),
            document_digest: digest,
            source_handle: source_handle.clone(),
        })
        .await?;
    let (status, id) = match result {
        AiImportEnqueueResult::Enqueued(id) => (StatusCode::ACCEPTED, id),
        AiImportEnqueueResult::Existing(id) => {
            // The bytes were stored under the freshly generated `job_id` before
            // the dedup lookup; the existing job references its own source
            // document, so this new handle is orphaned — remove it to avoid
            // leaking one full document per duplicate re-upload.
            if let Err(error) = state
                .ports
                .ai_document_store()
                .delete_source(&source_handle)
                .await
            {
                tracing::warn!(%error, "failed to remove orphaned AI import source document");
            }
            (StatusCode::OK, id)
        }
    };
    Ok((status, Json(id)))
}

/// Normalize the raw `Content-Type` header: lowercase + trimmed media type
/// without parameters, so `TEXT/CSV` and `text/csv ; charset=utf-8` both
/// match `text/csv`. Media types are case-insensitive (RFC 9110), and the
/// parameter list after `;` is not part of the type.
fn request_content_type(headers: &HeaderMap) -> String {
    headers
        .get("content-type")
        .and_then(|value| value.to_str().ok())
        .unwrap_or_default()
        .split(';')
        .next()
        .unwrap_or_default()
        .trim()
        .to_ascii_lowercase()
}

#[utoipa::path(
    post,
    path = "/ai-import/scripts",
    request_body(content = String, content_type = "application/pdf"),
    responses(
        (status = 200, body = AiImportJobId, description = "Duplicate upload — existing job id"),
        (status = 202, body = AiImportJobId, description = "Job enqueued"),
        (status = 404, body = ProblemDetails, description = "AI import disabled"),
        (status = 413, body = ProblemDetails, description = "Document exceeds the configured size limit"),
        (status = 415, body = ProblemDetails, description = "Unsupported media type"),
        (status = 403, body = ProblemDetails, description = "Not authorized")
    )
)]
pub async fn upload_ai_script<P: Ports>(
    State(state): State<AppState<P>>,
    current_user: CurrentUser,
    headers: HeaderMap,
    body: Bytes,
) -> ApiResult<AiImportJobId> {
    // AUTHZ-GATE: script uploads require active costume-department membership.
    let content_type = request_content_type(&headers);
    if content_type != "application/pdf" {
        return Err(ApiError::UnsupportedMediaType(
            "script imports require application/pdf",
        ));
    }
    enqueue_ai_upload(&state, current_user, headers, body, DocumentKind::Script).await
}

#[utoipa::path(
    post,
    path = "/ai-import/schedules",
    request_body(
        content = String,
        content_type = "application/pdf",
        content_type = "text/csv",
        content_type = "text/plain"
    ),
    responses(
        (status = 200, body = AiImportJobId, description = "Duplicate upload — existing job id"),
        (status = 202, body = AiImportJobId, description = "Job enqueued"),
        (status = 404, body = ProblemDetails, description = "AI import disabled"),
        (status = 413, body = ProblemDetails, description = "Document exceeds the configured size limit"),
        (status = 415, body = ProblemDetails, description = "Unsupported media type"),
        (status = 403, body = ProblemDetails, description = "Not authorized")
    )
)]
pub async fn upload_ai_schedule<P: Ports>(
    State(state): State<AppState<P>>,
    current_user: CurrentUser,
    headers: HeaderMap,
    body: Bytes,
) -> ApiResult<AiImportJobId> {
    // AUTHZ-GATE: schedule uploads require active costume-department membership.
    let content_type = request_content_type(&headers);
    if !matches!(
        content_type.as_str(),
        "application/pdf" | "text/csv" | "text/plain"
    ) {
        return Err(ApiError::UnsupportedMediaType(
            "schedule imports require text/csv, application/pdf or text/plain",
        ));
    }
    enqueue_ai_upload(&state, current_user, headers, body, DocumentKind::Schedule).await
}

#[derive(Debug, Clone, Serialize, ToSchema)]
pub struct AiImportJobResponse {
    pub job: breakdown_core::ai::AiImportJob,
}

#[utoipa::path(
    get,
    path = "/ai-import/jobs/{id}",
    params(("id" = Uuid, Path)),
    responses((status = 200, body = AiImportJobResponse), (status = 404, body = ProblemDetails))
)]
pub async fn get_ai_import_job<P: Ports>(
    State(state): State<AppState<P>>,
    current_user: CurrentUser,
    Path(id): Path<AiImportJobId>,
) -> Result<Response, ApiError> {
    // AUTHZ-GATE: job status is visible only to its submitting user.
    let job = state.ports.ai_import_queue().get(id).await?;
    let job = job.ok_or(ApiError::NotFound("AI import job not found"))?;
    authorize_ai_job(&state, &current_user, &job, Action::Read).await?;
    Ok(no_store_json(StatusCode::OK, AiImportJobResponse { job }))
}

#[utoipa::path(
    get,
    path = "/ai-import/jobs/{id}/preview",
    params(("id" = Uuid, Path)),
    responses((status = 200, body = Object), (status = 404, body = ProblemDetails))
)]
pub async fn get_ai_import_preview<P: Ports>(
    State(state): State<AppState<P>>,
    current_user: CurrentUser,
    Path(id): Path<AiImportJobId>,
) -> Result<Response, ApiError> {
    // AUTHZ-GATE: preview content is visible only to its submitting user.
    let job = state.ports.ai_import_queue().get(id).await?;
    let job = job.ok_or(ApiError::NotFound("AI import job not found"))?;
    authorize_ai_job(&state, &current_user, &job, Action::Read).await?;
    let handle = job.preview_handle.ok_or(ApiError::NotFound("AI preview"))?;
    let payload = state
        .ports
        .ai_preview_store()
        .get(&handle)
        .await?
        .ok_or(ApiError::NotFound("AI preview"))?;
    let value: serde_json::Value = serde_json::from_slice(&payload).map_err(|error| {
        tracing::error!(error = %error, "invalid AI preview JSON");
        ApiError::Validation("invalid AI preview JSON")
    })?;
    Ok(no_store_json(StatusCode::OK, value))
}

#[derive(Debug, Clone, Deserialize, ToSchema)]
pub struct ApplyAiImportRequest {
    pub episode_id: EpisodeId,
    pub series_id: Option<SeriesId>,
    pub mappings: Vec<ApplyMapping>,
    pub accept_as_is: bool,
    pub edit_distance: u32,
}

#[derive(Debug, Clone, Serialize, ToSchema)]
pub struct ApplyAiImportResponse {
    pub applied_count: u32,
    pub created_days: u32,
    pub planned_scene_shoots: u32,
}

#[utoipa::path(
    post,
    path = "/ai-import/jobs/{id}/apply",
    params(("id" = Uuid, Path)),
    request_body = ApplyAiImportRequest,
    responses((status = 200, body = ApplyAiImportResponse), (status = 403, body = ProblemDetails))
)]
pub async fn apply_ai_import<P: Ports>(
    State(state): State<AppState<P>>,
    current_user: CurrentUser,
    Path(id): Path<AiImportJobId>,
    Json(request): Json<ApplyAiImportRequest>,
) -> ApiResult<ApplyAiImportResponse> {
    // AUTHZ-GATE: applying an AI preview is a privileged production mutation.
    let job = state.ports.ai_import_queue().get(id).await?;
    let job = job.ok_or(ApiError::NotFound("AI import job not found"))?;
    authorize_ai_job(&state, &current_user, &job, Action::Write).await?;
    if job.status != breakdown_core::ai::JobStatus::Succeeded {
        return Err(ApiError::Conflict(
            "only a succeeded AI preview can be applied",
        ));
    }
    let handle = job
        .preview_handle
        .as_deref()
        .ok_or(ApiError::NotFound("AI preview"))?;
    let payload = state
        .ports
        .ai_preview_store()
        .get(handle)
        .await?
        .ok_or(ApiError::NotFound("AI preview"))?;
    // An accept-as-is outcome means the user made zero edits; a nonzero
    // edit_distance alongside it is contradictory and would persist an
    // invalid applied outcome (issue #171 review).
    if request.accept_as_is && request.edit_distance != 0 {
        return Err(ApiError::Validation(
            "accept_as_is requires edit_distance = 0",
        ));
    }
    let telemetry = Telemetry {
        doc_kind: Some(job.document_kind),
        // Apply reached: record the accept signal and the content-free edit
        // count. Zero edits on an accepted apply stays `edit_distance = 0`;
        // only never-applied jobs are `NotApplied` (NULL).
        apply_state: TelemetryApplyState::Applied {
            accept_as_is: request.accept_as_is,
            edit_distance: request.edit_distance,
        },
        ..Telemetry::default()
    };
    match job.document_kind {
        DocumentKind::Script => {
            // AUTHZ-GATE: resolve the target episode at the API edge and require
            // its block to match the job's block — a succeeded job in block A
            // must not create scenes in an episode from block B (CWE-639 IDOR).
            let episode = state
                .ports
                .episode_repo()
                .find_by_id(request.episode_id.0)
                .await?;
            if let Some(job_block) = job.block_id
                && episode.block_id != job_block
            {
                return Err(forbidden_ai_config());
            }
            // The episode is the authoritative source for the series seam;
            // resolving it here keeps the write side free of read-model lookups.
            let series_id = Some(episode.series_id);

            let preview: ScriptContext = serde_json::from_slice(&payload).map_err(|error| {
                tracing::error!(error = %error, "invalid ScriptContext preview");
                ApiError::Validation("invalid ScriptContext preview")
            })?;

            // AUTHZ-GATE (CWE-639): the client may supply `Update` decisions
            // referencing any aggregate id. Reject duplicate draft_refs and
            // mappings beyond the preview's scene count, then verify every
            // distinct update target is a scene in the job's resolved episode.
            // Duplicates are deduplicated so one apply cannot trigger an
            // unbounded number of repository reads.
            let mut seen_draft_refs = std::collections::HashSet::new();
            let mut seen_update_ids = std::collections::HashSet::new();
            for mapping in &request.mappings {
                if !seen_draft_refs.insert(mapping.draft_ref.clone()) {
                    return Err(ApiError::Validation(
                        "duplicate mapping for the same draft row",
                    ));
                }
                if let breakdown_core::ai::ApplyMappingDecision::Update { aggregate_id, .. } =
                    mapping.decision
                {
                    if !seen_update_ids.insert(aggregate_id) {
                        continue;
                    }
                    let scene = state.ports.scene_repo().find_by_id(aggregate_id).await?;
                    if scene.episode_id != EpisodeId::from_uuid(episode.id) {
                        return Err(forbidden_ai_config());
                    }
                }
            }
            if request.mappings.len() > preview.scenes.len() {
                return Err(ApiError::Validation(
                    "apply carries more mappings than the preview contains scenes",
                ));
            }
            let worker = ApplyWorker {
                scene_commands: Arc::new(state.ports.scene_commands().clone()),
                mappings: Arc::new(state.ports.ai_import_mapping().clone()),
                queue: Arc::new(state.ports.ai_import_queue().clone()),
            };
            let applied = worker
                .apply_script(ApplyScriptRequest {
                    actor: current_user.sub,
                    preview_id: id,
                    preview: &preview,
                    decisions: &request.mappings,
                    episode_id: request.episode_id,
                    series_id,
                    telemetry: Some(telemetry),
                })
                .await?;
            Ok((
                StatusCode::OK,
                Json(ApplyAiImportResponse {
                    applied_count: applied.len() as u32,
                    created_days: 0,
                    planned_scene_shoots: 0,
                }),
            ))
        }
        DocumentKind::Schedule => {
            let preview: MergedPreview = serde_json::from_slice(&payload).map_err(|error| {
                tracing::error!(error = %error, "invalid merged preview");
                ApiError::Validation("invalid merged preview")
            })?;
            let worker = ScheduleApplyWorker {
                scene_commands: Arc::new(state.ports.scene_commands().clone()),
                shooting_day_commands: Arc::new(state.ports.shooting_day_commands().clone()),
                scene_shoot_commands: Arc::new(state.ports.scene_shoot_commands().clone()),
                mappings: Arc::new(state.ports.ai_import_mapping().clone()),
            };
            let result = worker
                .apply(ScheduleApplyRequest {
                    actor: current_user.sub,
                    preview_id: id,
                    preview: &preview,
                    series_id: request.series_id,
                })
                .await?;
            // Telemetry is not part of the apply success contract: the mutation
            // already committed. Log a failed record so the client still sees
            // the successful apply result (mirrors the script branch).
            if let Err(error) = state
                .ports
                .ai_import_queue()
                .record_telemetry(id, telemetry)
                .await
            {
                tracing::warn!(
                    %error,
                    "failed to record AI import telemetry after successful schedule apply"
                );
            }
            Ok((
                StatusCode::OK,
                Json(ApplyAiImportResponse {
                    applied_count: 0,
                    created_days: result.created_days,
                    planned_scene_shoots: result.planned_scene_shoots,
                }),
            ))
        }
    }
}

#[derive(Debug, Clone, Deserialize, ToSchema)]
pub struct CreateAiConfigRequest {
    pub provider: LlmProvider,
    pub assistant_model: String,
    pub image_model: Option<String>,
    pub prompts: HashMap<DocumentKind, String>,
    pub vault_key_id: String,
}

#[derive(Debug, Clone, Deserialize, ToSchema)]
pub struct UpdateAiConfigRequest {
    pub provider: LlmProvider,
    pub assistant_model: String,
    pub image_model: Option<String>,
    pub prompts: HashMap<DocumentKind, String>,
    pub vault_key_id: String,
    pub version: AggregateVersion,
}

#[derive(Debug, Clone, Deserialize, ToSchema)]
pub struct RevokeAiConfigRequest {
    pub version: AggregateVersion,
}

async fn credential_role_gate<P: Ports>(
    state: &AppState<P>,
    user: &CurrentUser,
) -> Result<bool, ApiError> {
    // AUTHZ-GATE: AI configuration management requires an active credential
    // role — decided via the (fallible) credential-role policy so read-model
    // failures surface as mapped errors, not as a silent 403.
    let decision = state
        .authorization_policy
        .authorize_credential_role(&user.sub)
        .await?;
    Ok(decision == PolicyDecision::Allow)
}

fn forbidden_ai_config() -> ApiError {
    ApiError::Forbidden("not authorized to manage AI configuration")
}

/// Render a JSON response with `Cache-Control: no-store` — AI import job and
/// preview payloads are user-specific and must not be retained by browsers or
/// intermediary caches (CWE-525).
fn no_store_json<T: serde::Serialize>(status: StatusCode, value: T) -> Response {
    let mut response = (status, Json(value)).into_response();
    response
        .headers_mut()
        .insert(header::CACHE_CONTROL, HeaderValue::from_static("no-store"));
    response
}

#[utoipa::path(
    post,
    path = "/ai-import/config",
    request_body = CreateAiConfigRequest,
    responses((status = 201, body = IdVersionResponse), (status = 403, body = ProblemDetails))
)]
pub async fn create_ai_config<P: Ports>(
    State(state): State<AppState<P>>,
    current_user: CurrentUser,
    Json(request): Json<CreateAiConfigRequest>,
) -> ApiResult<IdVersionResponse> {
    // AUTHZ-GATE: only active credential-role members may create AI config.
    if !credential_role_gate(&state, &current_user).await? {
        return Err(forbidden_ai_config());
    }
    let id = Uuid::now_v7();
    let (id, version) = state
        .ports
        .ai_config_commands()
        .create(
            current_user.sub.clone(),
            CreateAiConfig {
                id,
                user_id: current_user.sub,
                provider: request.provider,
                assistant_model: request.assistant_model,
                image_model: request.image_model,
                prompts: request.prompts,
                vault_key_id: request.vault_key_id,
            },
        )
        .await?;
    Ok((StatusCode::CREATED, Json(IdVersionResponse { id, version })))
}

#[utoipa::path(
    get,
    path = "/ai-import/config/{id}",
    params(("id" = Uuid, Path)),
    responses((status = 200, body = AiConfigView), (status = 403, body = ProblemDetails))
)]
pub async fn get_ai_config<P: Ports>(
    State(state): State<AppState<P>>,
    current_user: CurrentUser,
    Path(id): Path<Uuid>,
) -> ApiResult<AiConfigView> {
    // AUTHZ-GATE: AI configuration is a credential-role-only view.
    if !credential_role_gate(&state, &current_user).await? {
        return Err(forbidden_ai_config());
    }
    let view = state.ports.ai_config_repo().find_by_id(id).await?;
    if view.user_id != current_user.sub {
        return Err(forbidden_ai_config());
    }
    Ok((StatusCode::OK, Json(view)))
}

#[utoipa::path(
    patch,
    path = "/ai-import/config/{id}",
    params(("id" = Uuid, Path)),
    request_body = UpdateAiConfigRequest,
    responses((status = 200, body = AggregateVersion), (status = 403, body = ProblemDetails))
)]
pub async fn update_ai_config<P: Ports>(
    State(state): State<AppState<P>>,
    current_user: CurrentUser,
    Path(id): Path<Uuid>,
    Json(request): Json<UpdateAiConfigRequest>,
) -> ApiResult<AggregateVersion> {
    // AUTHZ-GATE: AI configuration mutation requires credential role and ownership.
    if !credential_role_gate(&state, &current_user).await? {
        return Err(forbidden_ai_config());
    }
    let view = state.ports.ai_config_repo().find_by_id(id).await?;
    if view.user_id != current_user.sub {
        return Err(forbidden_ai_config());
    }
    let version = state
        .ports
        .ai_config_commands()
        .update(
            current_user.sub,
            UpdateAiConfig {
                id,
                provider: request.provider,
                assistant_model: request.assistant_model,
                image_model: request.image_model,
                prompts: request.prompts,
                vault_key_id: request.vault_key_id,
                version: request.version,
            },
        )
        .await?;
    Ok((StatusCode::OK, Json(version)))
}

#[utoipa::path(
    post,
    path = "/ai-import/config/{id}/revoke",
    params(("id" = Uuid, Path)),
    request_body = RevokeAiConfigRequest,
    responses((status = 200, body = AggregateVersion), (status = 403, body = ProblemDetails))
)]
pub async fn revoke_ai_config<P: Ports>(
    State(state): State<AppState<P>>,
    current_user: CurrentUser,
    Path(id): Path<Uuid>,
    Json(request): Json<RevokeAiConfigRequest>,
) -> ApiResult<AggregateVersion> {
    // AUTHZ-GATE: revoking the AI credential binding requires credential role and ownership.
    if !credential_role_gate(&state, &current_user).await? {
        return Err(forbidden_ai_config());
    }
    let view = state.ports.ai_config_repo().find_by_id(id).await?;
    if view.user_id != current_user.sub {
        return Err(forbidden_ai_config());
    }
    let version = state
        .ports
        .ai_config_commands()
        .revoke(
            current_user.sub,
            RevokeAiConfig {
                id,
                version: request.version,
            },
        )
        .await?;
    Ok((StatusCode::OK, Json(version)))
}

#[derive(Debug, Clone, Serialize, ToSchema)]
pub struct AiProviderInfo {
    pub provider: LlmProvider,
    /// Canonical lowercase path key for `/ai-import/providers/{provider}/models`.
    pub key: String,
}

#[utoipa::path(
    get,
    path = "/ai-import/providers",
    responses((status = 200, body = [AiProviderInfo]), (status = 403, body = ProblemDetails))
)]
pub async fn list_ai_providers<P: Ports>(
    State(state): State<AppState<P>>,
    current_user: CurrentUser,
) -> ApiResult<Vec<AiProviderInfo>> {
    // AUTHZ-GATE: provider/model discovery is a credential-administration
    // capability and must be checked inside the authenticated handler —
    // decided via the (fallible) credential-role policy.
    let decision = state
        .authorization_policy
        .authorize_credential_role(&current_user.sub)
        .await?;
    if decision != PolicyDecision::Allow {
        return Err(ApiError::Forbidden(
            "not authorized to discover AI providers",
        ));
    }
    if !state.ai_import_enabled {
        return Err(ApiError::NotFound("AI import is disabled"));
    }
    Ok((
        StatusCode::OK,
        // Delegate to the centralized provider registry (infra::ai::provider_registry).
        Json(
            infra::ai::list_providers()
                .into_iter()
                .map(|info| AiProviderInfo {
                    provider: info.variant,
                    key: info.key,
                })
                .collect::<Vec<_>>(),
        ),
    ))
}

#[utoipa::path(
    get,
    path = "/ai-import/providers/{provider}/models",
    params(("provider" = String, Path, description = "Curated provider key")),
    responses((status = 200, body = [ModelInfo]), (status = 422, body = ProblemDetails), (status = 403, body = ProblemDetails))
)]
pub async fn list_ai_models<P: Ports>(
    State(state): State<AppState<P>>,
    current_user: CurrentUser,
    Path(provider): Path<String>,
) -> ApiResult<Vec<ModelInfo>> {
    // AUTHZ-GATE: model discovery can reveal credential-backed integrations —
    // decided via the (fallible) credential-role policy.
    let decision = state
        .authorization_policy
        .authorize_credential_role(&current_user.sub)
        .await?;
    if decision != PolicyDecision::Allow {
        return Err(ApiError::Forbidden("not authorized to discover AI models"));
    }
    if !state.ai_import_enabled {
        return Err(ApiError::NotFound("AI import is disabled"));
    }
    let provider = parse_ai_provider(&provider)?;
    Ok((StatusCode::OK, Json(infra::ai::curated_models(provider))))
}

fn parse_ai_provider(value: &str) -> Result<LlmProvider, DomainError> {
    // Delegate to the centralized provider registry (infra::ai::provider_registry).
    infra::ai::resolve_provider(value)
        .ok_or_else(|| DomainError::validation(format!("unknown AI provider {value}")))
}

#[cfg(test)]
#[path = "ai_import_tests.rs"]
mod ai_import_tests;

/// Build the full Axum router using the concrete `ProductionPorts` bundle.
pub fn routes() -> Router<AppState<ProductionPorts>> {
    // Axum's `Bytes` extractor enforces a default 2 MB request limit; the AI
    // document bound is 20 MB by default. Raise the extractor limit to the same
    // configured bound so uploads up to `max_document_bytes` reach the handler
    // check (which returns PAYLOAD_TOO_LARGE for oversize bodies).
    let ai_document_limit = infra::ai::AiImportFeature::from_env()
        .bounds
        .max_document_bytes as usize;
    Router::new()
        .route(
            "/ai-import/scripts",
            routing::post(upload_ai_script::<ProductionPorts>),
        )
        .route(
            "/ai-import/schedules",
            routing::post(upload_ai_schedule::<ProductionPorts>),
        )
        // Raise the extractor limit only for the two AI upload routes; all other
        // routes keep Axum's default body limit.
        .route_layer(DefaultBodyLimit::max(ai_document_limit))
        .route(
            "/ai-import/jobs/{id}",
            routing::get(get_ai_import_job::<ProductionPorts>),
        )
        .route(
            "/ai-import/jobs/{id}/preview",
            routing::get(get_ai_import_preview::<ProductionPorts>),
        )
        .route(
            "/ai-import/jobs/{id}/apply",
            routing::post(apply_ai_import::<ProductionPorts>),
        )
        .route(
            "/ai-import/config",
            routing::post(create_ai_config::<ProductionPorts>),
        )
        .route(
            "/ai-import/config/{id}",
            routing::get(get_ai_config::<ProductionPorts>).patch(update_ai_config::<ProductionPorts>),
        )
        .route(
            "/ai-import/config/{id}/revoke",
            routing::post(revoke_ai_config::<ProductionPorts>),
        )
        .route(
            "/ai-import/providers",
            routing::get(list_ai_providers::<ProductionPorts>),
        )
        .route(
            "/ai-import/providers/{provider}/models",
            routing::get(list_ai_models::<ProductionPorts>),
        )
        .route(
            "/settings/gdrive",
            routing::post(create_gdrive_credential::<ProductionPorts>),
        )
        .route(
            "/settings/{id}/gdrive",
            routing::patch(rotate_gdrive_credential::<ProductionPorts>),
        )
        .route("/settings/credentials", routing::post(create_credential::<ProductionPorts>))
        .route(
            "/settings/{id}",
            routing::get(get_settings::<ProductionPorts>).delete(revoke_settings::<ProductionPorts>),
        )
        .route("/seasons", routing::post(create_season::<ProductionPorts>))
        .route("/seasons/{id}", routing::get(get_season::<ProductionPorts>))
        .route(
            "/seasons/{id}/membership",
            routing::get(get_season_membership::<ProductionPorts>),
        )
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
