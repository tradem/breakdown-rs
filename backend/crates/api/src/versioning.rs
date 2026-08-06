// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.2 (neuralwatt)

//! HTTP API path-versioning support (ADR-021).
//!
//! Routes are mounted under a `/v{n}` prefix (see [`crate::routes::app_router`])
//! and the OpenAPI `info.version` carries the path version string (`"v1"`).
//! This module provides the `Deprecation` / `Sunset` response-header
//! middleware that signals an open deprecation window (ADR-021 D4): the
//! moment `/v{n+1}` ships, every response of a `/v{n}` route must carry
//! `Deprecation: true` and `Sunset: <RFC-8594 date>` for at least 8 weeks.
//!
//! Today only `/v1` is served, so the registry is empty — the middleware is a
//! no-op until a breaking wire change cuts `/v2` (then the release owner
//! registers the deprecated `/v1` prefixes here and ships the next `api`
//! MAJOR, per ADR-020 D2 / ADR-021 D2).

use std::collections::HashMap;
use std::sync::Arc;

use axum::body::Body;
use axum::extract::State;
use axum::http::{HeaderValue, Request};
use axum::middleware::Next;
use axum::response::Response;

/// `Deprecation` response header emitted on deprecated routes (ADR-021 D4).
///
/// The `http` crate does not expose a constant for this draft-standard header
/// name yet, so it is declared here once.
pub const DEPRECATION_HEADER: &str = "deprecation";
/// `Sunset` response header (RFC 8594) carrying the window-end HTTP-date.
pub const SUNSET_HEADER: &str = "sunset";

/// Configuration error for the deprecation registry (release-time, ADR-021 D4).
#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
pub enum VersioningConfigError {
    /// The `Sunset` value is not a valid RFC 8594 HTTP-date.
    #[error("Sunset value {0:?} is not a valid RFC 8594 HTTP-date")]
    InvalidSunsetDate(String),
}

/// Registry of deprecated route prefixes → RFC-8594 `Sunset` HTTP-date.
///
/// Empty while only `/v1` is served. The release owner populates it in
/// `app_router` when a `/v{n+1}` ships, per ADR-021 D4 (minimum 8-week
/// window, `Sunset` = window end).
#[derive(Debug, Clone, Default)]
pub struct DeprecationRegistry {
    /// Path prefix of a deprecated route (e.g. `/v1/seasons`) → `Sunset`
    /// HTTP-date (e.g. `Thu, 01 Oct 2026 00:00:00 GMT`).
    routes: Arc<HashMap<String, String>>,
}

impl DeprecationRegistry {
    /// An empty registry — no route is currently deprecated.
    pub fn new() -> Self {
        Self::default()
    }

    /// Register a deprecated path prefix with its fixed `Sunset` HTTP-date.
    ///
    /// This is a release-time (not per-request) configuration: call it once
    /// while building the router, never from request handling. The date is
    /// validated as an RFC 8594 HTTP-date (IMF-fixdate, e.g.
    /// `Thu, 01 Oct 2026 00:00:00 GMT`) so a configuration typo fails at boot
    /// instead of emitting a malformed `Sunset` header on every response.
    pub fn deprecate(
        &mut self,
        path_prefix: impl Into<String>,
        sunset_http_date: impl Into<String>,
    ) -> Result<(), VersioningConfigError> {
        let sunset_http_date = sunset_http_date.into();
        httpdate::parse_http_date(&sunset_http_date)
            .map_err(|_| VersioningConfigError::InvalidSunsetDate(sunset_http_date.clone()))?;
        Arc::make_mut(&mut self.routes).insert(path_prefix.into(), sunset_http_date);
        Ok(())
    }

    /// Resolve the `Sunset` date for a request path, if it is deprecated.
    ///
    /// A route prefix matches only at a path-segment boundary: the request
    /// path equals the prefix or continues with `/` right after it (so
    /// `/v1/seasons` does not deprecate `/v1/seasons-old`). When several
    /// prefixes match (e.g. `/v1` and `/v1/seasons`), the longest — most
    /// specific — prefix wins.
    fn sunset_for(&self, path: &str) -> Option<&str> {
        self.routes
            .iter()
            .filter(|(prefix, _)| {
                path == prefix.as_str()
                    || path
                        .strip_prefix(prefix.as_str())
                        .is_some_and(|rest| rest.starts_with('/'))
            })
            .max_by_key(|(prefix, _)| prefix.len())
            .map(|(_, sunset)| sunset.as_str())
    }
}

/// Axum middleware: append `Deprecation: true` and `Sunset: <date>` headers
/// to every response of a deprecated route (ADR-021 D4).
///
/// The headers are appended only when the matched path falls into an open
/// deprecation window; otherwise the response passes through untouched.
pub async fn deprecation_middleware(
    State(registry): State<DeprecationRegistry>,
    req: Request<Body>,
    next: Next,
) -> Response {
    let path = req.uri().path().to_string();
    let mut response = next.run(req).await;
    if let Some(sunset) = registry.sunset_for(&path) {
        // `from_static` is infallible for the literal `"true"` (http 1.x).
        response
            .headers_mut()
            .insert(DEPRECATION_HEADER, HeaderValue::from_static("true"));
        if let Ok(value) = HeaderValue::from_str(sunset) {
            response.headers_mut().insert(SUNSET_HEADER, value);
        }
    }
    response
}

#[cfg(test)]
mod tests {
    use axum::Router;
    use axum::body::Body;
    use axum::http::Request;
    use axum::http::StatusCode;
    use axum::middleware;
    use tower::ServiceExt;

    use super::*;

    fn test_router(registry: DeprecationRegistry) -> Router<()> {
        Router::new()
            .route(
                "/v1/seasons",
                axum::routing::get(|| async { StatusCode::OK }),
            )
            .route(
                "/v1/blocks",
                axum::routing::get(|| async { StatusCode::OK }),
            )
            .layer(middleware::from_fn_with_state(
                registry,
                deprecation_middleware,
            ))
            .with_state(())
    }

    #[tokio::test]
    async fn current_version_has_no_deprecation_headers() {
        let app = test_router(DeprecationRegistry::new());
        let res = app
            .oneshot(
                Request::builder()
                    .uri("/v1/seasons")
                    .body(Body::empty())
                    .expect("request builds"),
            )
            .await
            .expect("router serves");
        assert_eq!(res.status(), StatusCode::OK);
        assert!(res.headers().get(DEPRECATION_HEADER).is_none());
        assert!(res.headers().get(SUNSET_HEADER).is_none());
    }

    #[tokio::test]
    async fn deprecated_route_carries_deprecation_and_sunset_headers() {
        let mut registry = DeprecationRegistry::new();
        registry
            .deprecate("/v1/seasons", "Thu, 01 Oct 2026 00:00:00 GMT")
            .expect("valid RFC 8594 date");
        let app = test_router(registry);
        let res = app
            .oneshot(
                Request::builder()
                    .uri("/v1/seasons")
                    .body(Body::empty())
                    .expect("request builds"),
            )
            .await
            .expect("router serves");
        assert_eq!(res.status(), StatusCode::OK);
        assert_eq!(
            res.headers()
                .get(DEPRECATION_HEADER)
                .map(|v| v.to_str().expect("ascii")),
            Some("true")
        );
        assert_eq!(
            res.headers()
                .get(SUNSET_HEADER)
                .map(|v| v.to_str().expect("ascii")),
            Some("Thu, 01 Oct 2026 00:00:00 GMT")
        );
    }

    #[tokio::test]
    async fn unrelated_route_stays_undeprecated() {
        let mut registry = DeprecationRegistry::new();
        registry
            .deprecate("/v1/seasons", "Thu, 01 Oct 2026 00:00:00 GMT")
            .expect("valid RFC 8594 date");
        let app = test_router(registry);
        let res = app
            .oneshot(
                Request::builder()
                    .uri("/v1/blocks")
                    .body(Body::empty())
                    .expect("request builds"),
            )
            .await
            .expect("router serves");
        assert_eq!(res.status(), StatusCode::OK);
        assert!(res.headers().get(DEPRECATION_HEADER).is_none());
        assert!(res.headers().get(SUNSET_HEADER).is_none());
    }

    #[test]
    fn deprecate_rejects_invalid_http_date() {
        let mut registry = DeprecationRegistry::new();
        let err = registry.deprecate("/v1/seasons", "not-a-date");
        assert_eq!(
            err,
            Err(VersioningConfigError::InvalidSunsetDate(
                "not-a-date".to_string()
            ))
        );
        // The registry stays empty — a bad config never reaches the wire.
        assert!(registry.routes.is_empty());
    }

    #[test]
    fn sunset_for_matches_only_complete_segments() {
        let mut registry = DeprecationRegistry::new();
        registry
            .deprecate("/v1/seasons", "Thu, 01 Oct 2026 00:00:00 GMT")
            .expect("valid RFC 8594 date");
        // Exact prefix and `/`-continuation match; partial segment does not.
        assert!(registry.sunset_for("/v1/seasons").is_some());
        assert!(registry.sunset_for("/v1/seasons/1").is_some());
        assert!(registry.sunset_for("/v1/seasons-old").is_none());
        assert!(registry.sunset_for("/v1/blocks").is_none());
    }

    #[test]
    fn sunset_for_prefers_longest_matching_prefix() {
        let mut registry = DeprecationRegistry::new();
        registry
            .deprecate("/v1", "Thu, 01 Oct 2026 00:00:00 GMT")
            .expect("valid RFC 8594 date");
        registry
            .deprecate("/v1/seasons", "Sun, 01 Nov 2026 00:00:00 GMT")
            .expect("valid RFC 8594 date");
        // Both prefixes match /v1/seasons; the more specific one wins.
        assert_eq!(
            registry.sunset_for("/v1/seasons"),
            Some("Sun, 01 Nov 2026 00:00:00 GMT")
        );
        // Only the broad prefix matches /v1/blocks.
        assert_eq!(
            registry.sunset_for("/v1/blocks"),
            Some("Thu, 01 Oct 2026 00:00:00 GMT")
        );
    }
}
