// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors

pub mod handlers;
pub mod routes;
pub mod state;

use utoipa::OpenApi;

/// OpenAPI document for the persistence-layer v1 endpoints (ADR-006).
#[derive(OpenApi)]
#[openapi(
    paths(
        handlers::create_scene,
        handlers::get_scene,
        handlers::list_scenes,
        handlers::update_scene_details,
        handlers::create_character,
        handlers::get_character,
        handlers::list_characters,
        handlers::update_measurements,
        handlers::create_costume,
        handlers::get_costume,
        handlers::list_costumes,
        handlers::update_costume_notes,
        handlers::create_calculation,
        handlers::get_calculation,
        handlers::list_calculations,
        handlers::update_calculation_header,
    ),
    components(schemas(
        handlers::IdVersionResponse,
        handlers::ErrorResponse,
        handlers::CreateSceneRequest,
        handlers::CreateCharacterRequest,
        handlers::CreateCostumeRequest,
        handlers::CreateCalculationRequest,
        handlers::UpdateSceneDetailsRequest,
        handlers::UpdateMeasurementsRequest,
        handlers::UpdateCostumeNotesRequest,
        handlers::UpdateHeaderInfoRequest,
        breakdown_core::scene::views::SceneView,
        breakdown_core::character::views::CharacterView,
        breakdown_core::costume::views::CostumeView,
        breakdown_core::costume::views::CostumeDetailView,
        breakdown_core::costume::views::CostumePhotoView,
        breakdown_core::calculation::views::CalculationView,
        breakdown_core::calculation::views::CalculationItemView,
        breakdown_core::scene::events::SceneDetails,
        breakdown_core::character::events::CharacterMeasurements,
        breakdown_core::character::events::ContactInfo,
        breakdown_core::costume::events::CostumeDetail,
        breakdown_core::calculation::events::CalculationHeader,
        breakdown_core::shared::AggregateVersion,
        breakdown_core::shared::ProjectId,
    )),
    tags(
        (name = "Scenes", description = "Scene read/write endpoints"),
        (name = "Characters", description = "Character read/write endpoints"),
        (name = "Costumes", description = "Costume read/write endpoints"),
        (name = "Calculations", description = "Calculation read/write endpoints"),
    )
)]
pub struct ApiDoc;
