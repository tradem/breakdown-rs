// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors

//! Route-coverage tests: enumerate every API route from the OpenAPI spec and
//! verify it has a deliberate authentication + authorization requirement.
//!
//! # Why this exists
//!
//! The [`api::routes::app_router`] wraps [`api::handlers::routes`] with an
//! outer [`api::auth::auth_middleware`] layer, so **all** API routes are
//! structurally behind authentication.  The inner
//! [`api::auth::authorize_middleware`] then applies the per-route authorization
//! requirement (authenticated-only vs. active-block-member).
//!
//! This test acts as a **living inventory** that forces a deliberate decision
//! for every route.  When you add a new endpoint you **must** also add it to
//! the [`api::ApiDoc`] openapi annotation **and** to
//! [`api::auth::authorization::requirement_for`]; this test then documents the
//! chosen requirement level.

use api::ApiDoc;
use api::auth::authorization::{Requirement, requirement_for};
use utoipa::OpenApi;

/// Collect every path from the OpenAPI spec and return two lists:
///
/// 1. `api_routes` — non-swagger paths (behind the auth middleware).
/// 2. `swagger_routes` — paths under `/swagger-ui` or `/api-docs` (excluded
///    from auth).
fn partition_paths() -> (Vec<String>, Vec<String>) {
    let doc = ApiDoc::openapi();
    let json = serde_json::to_value(&doc).expect("ApiDoc must serialize to JSON");

    let paths = json["paths"]
        .as_object()
        .expect("ApiDoc must contain a \"paths\" object");

    assert!(!paths.is_empty(), "ApiDoc must define at least one path");

    let mut api = Vec::new();
    let mut swagger = Vec::new();

    for path in paths.keys() {
        if path.starts_with("/swagger-ui") || path.starts_with("/api-docs") {
            swagger.push(path.clone());
        } else {
            api.push(path.clone());
        }
    }

    api.sort();
    swagger.sort();
    (api, swagger)
}

#[test]
fn api_routes_are_behind_auth_middleware() {
    let (api, _swagger) = partition_paths();

    // Every route defined in `handlers::routes()` is wrapped by
    // `auth_middleware` in `app_router()`.  The only non-auth routes are
    // swagger-ui/api-docs which are nested separately.  This assertion
    // documents the expected total so that adding/removing a route forces a
    // conscious update.
    //
    // To update this count after adding or removing a route:
    //   1. Add/remove the handler in `api::handlers::mod.rs`.
    //   2. Update `api::ApiDoc` in `api::lib.rs`.
    //   3. Optionally add a rule in `requirement_for()` if the new route
    //      should be `Authenticated` rather than the default `BlockMember`.
    //   4. Run the test, see the new count, and update this assertion.
    //
    // (Each route may register multiple HTTP methods — we count path
    //  patterns, not method-verb pairs.)
    assert_eq!(
        api.len(),
        41,
        "number of API route path patterns has changed — \
         see doc comment above for update instructions"
    );
}

#[test]
fn api_routes_have_deliberate_authorization_requirement() {
    let (api, _swagger) = partition_paths();

    // Map from path pattern → expected requirement.
    //
    // This is the **explicit** inventory.  Every path must be listed here with
    // its intended authorization level.  The test fails if:
    //   • A path is not in this map (new route without a documented decision)
    //   • A path's actual requirement doesn't match the documented expectation
    //
    // Rules of thumb:
    //   `Authenticated` — season-scoped endpoints, block CRUD/listing,
    //                     invitation acceptance, and photo endpoints (which
    //                     have handler-internal season-scoped auth gates).
    //   `BlockMember`   — everything else: block-scoped read/write operations
    //                     that require active membership in the active block.
    let expected: &[(&str, Requirement)] = &[
        // Seasons — season context, not block-scoped
        ("/seasons", Requirement::Authenticated),
        ("/seasons/{id}", Requirement::Authenticated),
        ("/seasons/{id}/name", Requirement::Authenticated),
        (
            "/seasons/{season_id}/costume-categories",
            Requirement::Authenticated,
        ),
        // Blocks — creation/listing is Authenticated
        ("/blocks", Requirement::Authenticated),
        ("/blocks/{id}", Requirement::BlockMember),
        ("/blocks/{id}/audit", Requirement::BlockMember),
        ("/blocks/{id}/members", Requirement::BlockMember),
        ("/blocks/{id}/members/accept", Requirement::Authenticated),
        ("/blocks/{id}/members/leave", Requirement::BlockMember),
        ("/blocks/{id}/members/{user_id}", Requirement::BlockMember),
        (
            "/blocks/{id}/members/{user_id}/role",
            Requirement::BlockMember,
        ),
        ("/blocks/{id}/time-span", Requirement::BlockMember),
        // Episodes — scoped under block, need membership
        ("/episodes", Requirement::BlockMember),
        ("/episodes/{id}", Requirement::BlockMember),
        ("/episodes/{id}/name", Requirement::BlockMember),
        (
            "/episodes/{episode_id}/shooting-days",
            Requirement::BlockMember,
        ),
        // Scenes
        ("/scenes", Requirement::BlockMember),
        ("/scenes/{id}", Requirement::BlockMember),
        ("/scenes/{id}/details", Requirement::BlockMember),
        ("/scenes/{id}/characters", Requirement::BlockMember),
        (
            "/scenes/{id}/characters/{character_id}",
            Requirement::BlockMember,
        ),
        ("/scenes/{id}/shooting-days", Requirement::BlockMember),
        (
            "/scenes/{id}/shooting-days/{shooting_day_id}",
            Requirement::BlockMember,
        ),
        // Shooting days
        ("/shooting-days/{id}", Requirement::BlockMember),
        ("/shooting-days/{id}/archive", Requirement::BlockMember),
        // Characters — scoped under season, but accessed via block context
        ("/characters", Requirement::BlockMember),
        ("/characters/{id}", Requirement::BlockMember),
        ("/characters/{id}/measurements", Requirement::BlockMember),
        ("/characters/{id}/contact", Requirement::BlockMember),
        // Costumes
        ("/costumes", Requirement::BlockMember),
        ("/costumes/{id}", Requirement::BlockMember),
        ("/costumes/{id}/notes", Requirement::BlockMember),
        ("/costumes/{id}/assign", Requirement::BlockMember),
        ("/costumes/{id}/unassign", Requirement::BlockMember),
        ("/costumes/{id}/details", Requirement::BlockMember),
        // Costume categories — id-based PATCH/archive needs membership
        ("/costume-categories/{id}", Requirement::BlockMember),
        ("/costume-categories/{id}/archive", Requirement::BlockMember),
        // Photos — Authenticated at middleware level,
        // handler-internal season-scoped auth gate (see AGENTS.md §7)
        ("/costumes/{costume_id}/photos", Requirement::Authenticated),
        (
            "/costumes/{costume_id}/photos/{photo_id}",
            Requirement::Authenticated,
        ),
        (
            "/costumes/{costume_id}/photos/{photo_id}/bytes",
            Requirement::Authenticated,
        ),
    ];

    let mut failures: Vec<String> = Vec::new();
    let mut documented: std::collections::HashSet<&str> = std::collections::HashSet::new();

    for (path, want) in expected {
        documented.insert(*path);
        let got = requirement_for(path);
        if got != *want {
            failures.push(format!("  {:<55} expected {want:?}, got {got:?}", path));
        }
    }

    // Every path from the OpenAPI spec must have a documented expectation.
    for path in &api {
        if !documented.contains(path.as_str()) {
            failures.push(format!(
                "  {:<55} MISSING from expected table — \
                 add entry with deliberate requirement",
                path
            ));
        }
    }

    assert!(
        failures.is_empty(),
        "Route-authorization mismatches ({count}):\n{failures}\n\n\
         To fix: add/update the `expected` table in this test with the correct\n\
         requirement for each route.  See the doc comment on \
         `api_routes_are_behind_auth_middleware`.",
        count = failures.len(),
        failures = failures.join("\n"),
    );
}

/// The OpenAPI spec generated by [`ApiDoc`] does **not** include Swagger-UI
/// paths — those are served separately via `utoipa_swagger_ui::SwaggerUi` and
/// explicitly excluded from authentication in [`api::auth::auth_middleware`].
///
/// This test documents that:
/// 1. No Swagger paths leak into the ApiDoc (they come from a separate
///    `Router` merge in `app_router`).
/// 2. No API path accidentally starts with a swagger prefix (which would
///    cause it to bypass auth_middleware by mistake).
#[test]
fn swagger_routes_are_excluded_from_auth_middleware() {
    // auth_middleware (mod.rs:266-272) skips these prefixes.
    let skip_prefixes = ["/swagger-ui", "/api-docs"];

    // Swagger paths are NOT in the ApiDoc — they come from the SwaggerUi layer.
    let (api, swagger) = partition_paths();
    assert!(
        swagger.is_empty(),
        "Swagger paths found in ApiDoc — they belong to the SwaggerUi layer: {swagger:?}",
    );

    // Every API path must NOT start with a swagger prefix.
    for path in &api {
        for prefix in &skip_prefixes {
            assert!(
                !path.starts_with(prefix),
                "API path `{path}` starts with swagger prefix `{prefix}` \
                 — it would accidentally bypass auth_middleware",
            );
        }
    }
}
