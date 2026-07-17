// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors

pub mod auth;
pub mod handlers;
pub mod routes;
pub mod state;

use utoipa::OpenApi;

/// OpenAPI document for the persistence-layer v1 endpoints (ADR-006).
#[derive(OpenApi)]
#[openapi(
    paths(
        handlers::create_season,
        handlers::get_season,
        handlers::rename_season,
        handlers::create_block,
        handlers::get_block,
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
    ),
    components(schemas(
        handlers::IdVersionResponse,
        handlers::ErrorResponse,
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
        breakdown_core::scene::views::SceneView,
        breakdown_core::character::views::CharacterView,
        breakdown_core::character::category::CharacterCategory,
        breakdown_core::costume::views::CostumeView,
        breakdown_core::costume::views::CostumeDetailView,
        breakdown_core::costume::views::CostumePhotoView,
        breakdown_core::season::views::SeasonView,
        breakdown_core::block::views::BlockView,
        breakdown_core::episode::views::EpisodeView,
        breakdown_core::scene::events::SceneDetails,
        breakdown_core::character::events::CharacterMeasurements,
        breakdown_core::character::events::ContactInfo,
        breakdown_core::costume::events::CostumeDetail,
        breakdown_core::shared::AggregateVersion,
        breakdown_core::shared::EpisodeId,
        breakdown_core::shared::SeasonId,
        breakdown_core::shared::SeriesId,
        breakdown_core::shared::BlockId,
    )),
    tags(
        (name = "Seasons", description = "Production hierarchy: Series > Season"),
        (name = "Blocks", description = "Production hierarchy: Season > Block"),
        (name = "Episodes", description = "Production hierarchy: Season > Episode"),
        (name = "Scenes", description = "Scene read/write endpoints (scoped to an Episode)"),
        (name = "Characters", description = "Character read/write endpoints (scoped to a Season)"),
        (name = "Costumes", description = "Costume read/write endpoints (scope-free; bound to a Character)"),
    )
)]
pub struct ApiDoc;
