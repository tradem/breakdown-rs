// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: gpt-5.6-luna (opencode-go)
// Co-authored-by: deepseek-v4-flash (opencode-go)

#![cfg_attr(test, allow(clippy::unwrap_used, clippy::expect_used, clippy::panic))]
#![cfg_attr(
    test,
    allow(clippy::print_stdout, clippy::print_stderr, clippy::dbg_macro)
)]
pub mod auth;
pub mod handlers;
pub mod problems;
pub mod routes;
pub mod state;
pub mod tls_config;
pub mod versioning;

use utoipa::OpenApi;

/// OpenAPI document for the persistence-layer v1 endpoints (ADR-006),
/// formalised by ADR-021: routes are mounted under `/v1` and `info.version`
/// is the API path version string (`"v1"`).
///
/// The `/v1` path prefix is applied at runtime by [`api_doc`] (utoipa 5.5's
/// `#[openapi]` derive does not support a global `context_path`), so the
/// generated spec always matches the mounted wire contract.
#[derive(OpenApi)]
#[openapi(
    info(
        title = "Breakdown RS API",
        description = "Costume scheduling API for Breakdown RS (ADR-006). Routes are mounted under the /v1 path prefix; the path version is bumped only on a breaking wire change (ADR-021).",
        version = "v1"
    ),
    paths(
        handlers::create_season,
        handlers::get_season,
        handlers::rename_season,
        handlers::create_block,
        handlers::get_block,
        handlers::get_block_audit,
        handlers::invite_member,
        handlers::accept_invitation,
        handlers::grant_role,
        handlers::remove_member,
        handlers::leave_block,
        handlers::list_members,
        handlers::get_member,
        handlers::list_blocks,
        handlers::update_block_time_span,
        handlers::create_episode,
        handlers::get_episode,
        handlers::list_episodes,
        handlers::rename_episode,
        handlers::create_scene,
        handlers::get_scene,
        handlers::list_scenes,
        handlers::update_scene_details,
        handlers::assign_scene_character,
        handlers::remove_scene_character,
        handlers::create_shooting_day,
        handlers::list_shooting_days,
        handlers::get_shooting_day,
        handlers::update_shooting_day,
        handlers::archive_shooting_day,
        handlers::schedule_scene_on_shooting_day,
        handlers::unschedule_scene_from_shooting_day,
        handlers::create_character,
        handlers::get_character,
        handlers::list_characters,
        handlers::update_measurements,
        handlers::update_contact_info,
        handlers::create_costume,
        handlers::get_costume,
        handlers::list_costumes,
        handlers::update_costume_notes,
        handlers::assign_costume,
        handlers::unassign_costume,
        handlers::add_costume_detail,
        handlers::create_costume_category,
        handlers::list_costume_categories,
        handlers::update_costume_category,
        handlers::archive_costume_category,
        handlers::upload_costume_photo,
        handlers::get_costume_photo_bytes,
        handlers::delete_costume_photo,
        handlers::dispo_report_pdf,
        handlers::shoot_day_report_pdf,
        handlers::planned_vs_actual_report_pdf,
        handlers::manual_archive_reports,
        handlers::create_credential,
        handlers::list_ai_providers,
        handlers::list_ai_models,
        handlers::create_ai_config,
        handlers::get_ai_config,
        handlers::update_ai_config,
        handlers::revoke_ai_config,
        handlers::upload_ai_script,
        handlers::upload_ai_schedule,
        handlers::get_ai_import_job,
        handlers::get_ai_import_preview,
        handlers::apply_ai_import,
        handlers::create_gdrive_credential,
        handlers::rotate_gdrive_credential,
        handlers::get_settings,
        handlers::revoke_settings,
    ),
    components(schemas(
        handlers::IdVersionResponse,
        crate::problems::ProblemDetails,
        handlers::ManualArchiveResponse,
        handlers::ManualArchiveJobResult,
        handlers::CreateSceneRequest,
        handlers::CreateCharacterRequest,
        handlers::CreateCostumeRequest,
        handlers::CreateSeasonRequest,
        handlers::CreateBlockRequest,
        handlers::CreateEpisodeRequest,
        handlers::UpdateSceneDetailsRequest,
        handlers::UpdateMeasurementsRequest,
        handlers::UpdateContactInfoRequest,
        handlers::UpdateCostumeNotesRequest,
        handlers::RenameSeasonRequest,
        handlers::RenameEpisodeRequest,
        handlers::UpdateBlockTimeSpanRequest,
        handlers::VersionRequest,
        handlers::AssignCharacterRequest,
        handlers::AssignCostumeRequest,
        handlers::PhotoBytesQuery,
        breakdown_core::scene::views::SceneView,
        breakdown_core::character::views::CharacterView,
        breakdown_core::character::category::CharacterCategory,
        breakdown_core::costume::views::CostumeView,
        breakdown_core::costume::views::CostumeDetailView,
        breakdown_core::costume::views::CostumePhotoView,
        breakdown_core::season::views::SeasonView,
        breakdown_core::block::views::BlockView,
        breakdown_core::audit::views::AuditEntry,
        handlers::InviteMemberRequest,
        handlers::GrantRoleRequest,
        handlers::CreateCostumeCategoryRequest,
        handlers::UpdateCostumeCategoryRequest,
        handlers::AddCostumeDetailRequest,
        handlers::CreateShootingDayRequest,
        handlers::UpdateShootingDayRequest,
        handlers::CreateCredentialRequest,
        handlers::GDriveCredentialRequest,
        handlers::GDriveCredentialUpdateRequest,
        handlers::CreateAiConfigRequest,
        handlers::UpdateAiConfigRequest,
        handlers::RevokeAiConfigRequest,
        handlers::AiImportJobResponse,
        handlers::ApplyAiImportRequest,
        handlers::ApplyAiImportResponse,
        breakdown_core::ai::AiImportJob,
        breakdown_core::ai::AiConfigView,
        breakdown_core::ai::LlmProvider,
        breakdown_core::ai::ModelInfo,
        breakdown_core::settings::views::SettingsView,
        breakdown_core::settings::views::CredentialBindingState,
        handlers::ScheduleSceneRequest,
        breakdown_core::membership::views::MembershipView,
        breakdown_core::membership::Role,
        breakdown_core::membership::views::MembershipStateKind,
        breakdown_core::episode::views::EpisodeView,
        breakdown_core::scene::events::SceneDetails,
        breakdown_core::character::events::CharacterMeasurements,
        breakdown_core::character::events::ContactInfo,
        breakdown_core::costume::events::CostumeDetail,
        breakdown_core::costume_category::views::CostumeCategoryView,
        breakdown_core::shared::AggregateVersion,
        breakdown_core::shared::EpisodeId,
        breakdown_core::shared::SeasonId,
        breakdown_core::shared::SeriesId,
        breakdown_core::shared::BlockId,
        breakdown_core::shared::ShootingDayId,
        breakdown_core::shared::LexicalSortKey,
        breakdown_core::shared::PhotoId,
        breakdown_core::shared::PhotoVariant,
        breakdown_core::shared::VariantStatus,
        breakdown_core::photo::views::PhotoView,
        breakdown_core::photo::views::PhotoVariantView,
        breakdown_core::shooting_day::views::ShootingDayView,
        breakdown_core::shooting_day::events::ShootingDaySource,
    )),
    tags(
        (name = "Seasons", description = "Production hierarchy: Series > Season"),
        (name = "Blocks", description = "Production hierarchy: Season > Block"),
        (name = "Episodes", description = "Production hierarchy: Season > Episode"),
        (name = "Scenes", description = "Scene read/write endpoints (scoped to an Episode)"),
        (name = "Characters", description = "Character read/write endpoints (scoped to a Season)"),
        (name = "Costumes", description = "Costume read/write endpoints (scope-free; bound to a Character)"),
        (name = "Photos", description = "Costume photo upload/download/delete endpoints"),
    )
)]
pub struct ApiDoc;

/// Build the OpenAPI document for the served wire contract (ADR-021 D1).
///
/// `info.version` is the API path version string (`"v1"`) and every
/// documented path is prefixed with the `/v1` context path, so the generated
/// spec always matches the mounted routes exactly. utoipa 5.5's `#[openapi]`
/// derive has no global `context_path`, so the prefix is applied here once
/// (single source of truth shared by the Swagger UI and the route-coverage
/// tests).
pub fn api_doc() -> utoipa::openapi::OpenApi {
    let mut doc = ApiDoc::openapi();
    doc.info.version = "v1".to_string();
    doc.info.title = "Breakdown RS API".to_string();
    doc.info.description = Some(
        "Costume scheduling API for Breakdown RS (ADR-006). Routes are mounted \
         under the /v1 path prefix; the path version is bumped only on a \
         breaking wire change (ADR-021).\n\
         Error contract (ADR-031): every error response (status ≥ 400) is an \
         RFC 9457 `application/problem+json` document carrying a stable \
         `code` (`{context}.{reason}` kebab-case) and a `trace_id` extension. \
         The full code registry is exposed under `x-code-registry`; per-code \
         documentation lives at `docs/errors/`."
            .to_string(),
    );
    // Prefix every documented path with the /v1 context path (ADR-021 D1).
    doc.paths.paths = doc
        .paths
        .paths
        .into_iter()
        .map(|(path, item)| (format!("/v1{path}"), item))
        .collect();

    // ADR-031 D1: every documented error response must carry the RFC 9457
    // media type. utoipa emits `application/json` for `body = ProblemDetails`;
    // we rewrite the media type centrally so the spec matches the wire
    // contract (single source of truth — no per-handler annotation drift).
    use utoipa::openapi::RefOr;
    for path_item in doc.paths.paths.values_mut() {
        for operation in [
            path_item.get.as_mut(),
            path_item.put.as_mut(),
            path_item.post.as_mut(),
            path_item.delete.as_mut(),
            path_item.options.as_mut(),
            path_item.head.as_mut(),
            path_item.patch.as_mut(),
            path_item.trace.as_mut(),
        ]
        .into_iter()
        .flatten()
        {
            for response in operation.responses.responses.values_mut() {
                let RefOr::T(response) = response else {
                    continue;
                };
                let mut renamed: indexmap::IndexMap<String, utoipa::openapi::Content> =
                    indexmap::IndexMap::new();
                for (media_type, content) in std::mem::take(&mut response.content) {
                    let is_problem = matches!(
                        &content.schema,
                        Some(RefOr::Ref(reference))
                            if reference.ref_location.ends_with("/ProblemDetails")
                    );
                    let key = if is_problem {
                        "application/problem+json".to_string()
                    } else {
                        media_type.clone()
                    };
                    renamed.insert(key, content);
                }
                response.content = renamed;
            }
        }
    }

    // Registry-woven docs (ADR-031 D2): the code registry is published as a
    // machine-readable extension so clients and tooling can validate codes
    // against the spec without scraping docs pages.
    doc.extensions.get_or_insert_default().insert(
        "x-code-registry".to_string(),
        serde_json::json!(
            breakdown_core::error_registry::PROBLEM_CODES
                .iter()
                .map(|entry| {
                    serde_json::json!({
                        "code": entry.code,
                        "status": entry.status,
                        "title": entry.title,
                        "type": entry.type_uri(),
                        "extensions": entry.extensions,
                    })
                })
                .collect::<Vec<_>>()
        ),
    );

    doc
}
