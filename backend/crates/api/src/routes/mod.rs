// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors

//! Router-Definitionen

use axum::Router;
use utoipa::OpenApi;
use utoipa_swagger_ui::SwaggerUi;

use crate::handlers;
use crate::state::{AppState, ProductionPorts};

/// Build the full Axum application router including API routes and Swagger UI.
pub fn app_router() -> Router<AppState<ProductionPorts>> {
    let doc = crate::ApiDoc::openapi();
    let swagger: Router<()> =
        Router::<()>::new().merge(SwaggerUi::new("/swagger-ui").url("/api-docs/openapi.json", doc));
    handlers::routes().nest_service("/swagger-ui", swagger)
}
