// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4-flash (opencode-go)

//! Router-Definitionen

use std::sync::Arc;

use axum::Router;
use axum::middleware;
use tower::ServiceBuilder;
use tower_http::catch_panic::CatchPanicLayer;
use utoipa_swagger_ui::SwaggerUi;

use crate::auth::{AuthState, AuthorizationState, auth_middleware, authorize_middleware};
use crate::handlers;
use crate::problems::{self, locale::negotiate_language, route_not_found};
use crate::state::{AppState, ProductionPorts};
use crate::versioning::{DeprecationRegistry, deprecation_middleware};

/// Apply the production middleware stack around a versioned API router:
/// `auth` (outermost) → `authorize` → `deprecation` (innermost).
///
/// Composed with `tower::ServiceBuilder` so the declaration order equals the
/// request order (bare `Router::layer` calls would apply the LAST-added layer
/// first, running authorization before authentication). This builder is the
/// single source of truth for the composition — `app_router` and the
/// composition regression test (`handler_authz.rs`) both invoke it, so the
/// production order cannot drift from what the test covers.
pub fn apply_api_middleware<S>(
    api: Router<S>,
    auth: Arc<AuthState>,
    authz: Arc<AuthorizationState>,
    deprecations: DeprecationRegistry,
) -> Router<S>
where
    S: Clone + Send + Sync + 'static,
{
    api.layer(
        ServiceBuilder::new()
            // Outermost: negotiate `Accept-Language` once so even auth
            // rejections render a localized problem `detail` (ADR-031 D5).
            .layer(middleware::from_fn(negotiate_language))
            .layer(middleware::from_fn_with_state(auth, auth_middleware))
            .layer(middleware::from_fn_with_state(authz, authorize_middleware))
            .layer(middleware::from_fn_with_state(
                deprecations,
                deprecation_middleware,
            )),
    )
}

/// Build the full Axum application router including API routes and Swagger UI.
///
/// The `AuthLayer` runs first (outermost): it validates the OIDC token and
/// attaches a `CurrentUser`. The `AuthorizationLayer` runs next and gates
/// block-scoped endpoints by active membership in the active block. Both layers
/// are supplied via `Arc` state so they are shareable across requests.
///
/// ADR-021 D1: every API route is mounted under the `/v1` path prefix (a
/// one-time additive re-mount). Swagger UI stays outside the versioned tree.
/// The `DeprecationLayer` (innermost) appends `Deprecation` / `Sunset` headers
/// to deprecated `/v{n}` routes during an open deprecation window — the
/// registry is empty while `/v1` is the only served version.
pub fn app_router(
    auth: Arc<AuthState>,
    authz: Arc<AuthorizationState>,
) -> Router<AppState<ProductionPorts>> {
    // Empty while only `/v1` is served; populated when `/v{n+1}` ships
    // (ADR-021 D4) — release-time configuration, not per-request.
    let deprecations = DeprecationRegistry::new();
    let api = apply_api_middleware(
        Router::new()
            .nest("/v1", handlers::routes())
            // ADR-031 D3: unknown routes are a problem document, not an
            // empty 404 (http-error-surface spec). The fallback lives on
            // the outer router; axum falls through to it for unmatched
            // nested `/v1` paths too.
            .fallback(route_not_found),
        auth,
        authz,
        deprecations,
    );

    // Panic catch-all (ADR-031 D3): any panic in the api stack (auth
    // middleware included) becomes a static `http.internal-error` problem
    // with the request trace id. Placed outside the middleware stack (so it
    // wraps auth), and inside TraceLayer (added in main.rs).
    let api = api.layer(CatchPanicLayer::custom(problems::panic_response));

    let doc = crate::api_doc();
    let swagger: Router<()> =
        Router::<()>::new().merge(SwaggerUi::new("/swagger-ui").url("/api-docs/openapi.json", doc));

    // Swagger UI is nested inside the layered API router but is explicitly
    // exempted by both middleware layers (path check), so it stays public.
    api.nest_service("/swagger-ui", swagger)
}
