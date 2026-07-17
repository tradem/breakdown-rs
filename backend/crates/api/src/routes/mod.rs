// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors

//! Router-Definitionen

use std::sync::Arc;

use axum::Router;
use axum::middleware;
use utoipa::OpenApi;
use utoipa_swagger_ui::SwaggerUi;

use crate::auth::{AuthState, AuthorizationState, auth_middleware, authorize_middleware};
use crate::handlers;
use crate::state::{AppState, ProductionPorts};

/// Build the full Axum application router including API routes and Swagger UI.
///
/// The `AuthLayer` runs first (outermost): it validates the OIDC token and
/// attaches a `CurrentUser`. The `AuthorizationLayer` runs next and gates
/// block-scoped endpoints by active membership in the active block. Both layers
/// are supplied via `Arc` state so they are shareable across requests.
pub fn app_router(
    auth: Arc<AuthState>,
    authz: Arc<AuthorizationState>,
) -> Router<AppState<ProductionPorts>> {
    let api = handlers::routes()
        .layer(middleware::from_fn_with_state(auth, auth_middleware))
        .layer(middleware::from_fn_with_state(authz, authorize_middleware));

    let doc = crate::ApiDoc::openapi();
    let swagger: Router<()> =
        Router::<()>::new().merge(SwaggerUi::new("/swagger-ui").url("/api-docs/openapi.json", doc));

    // Swagger UI is nested inside the layered API router but is explicitly
    // exempted by both middleware layers (path check), so it stays public.
    api.nest_service("/swagger-ui", swagger)
}
