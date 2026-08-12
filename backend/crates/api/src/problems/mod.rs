// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: kimi-k3 (neuralwatt)

//! RFC 9457 problem-detail error surface (ADR-031).
//!
//! One shared implementation of the `application/problem+json` envelope for
//! *every* error source: domain errors, auth middleware rejections, extractor
//! rejections, unknown routes, payload limits, and the panic fallback. The
//! envelope shape, content type, and trace capture live here — exactly one
//! implementation (ADR-031 D1).
//!
//! Codes are registered in `breakdown_core::error_registry` (dependency-free
//! data in `core`); this module only renders them. Tranche 3 adds server-side
//! `detail` localization (Fluent) behind the same builder.

use axum::body::Bytes as AxumBytes;
use axum::http::{StatusCode, header, request::Parts};
use axum::response::{IntoResponse, Response};
use breakdown_core::error::DomainError;
use breakdown_core::error_registry::{
    CONCURRENCY_VERSION_MISMATCH, DOMAIN_CONFLICT, DOMAIN_FORBIDDEN, DOMAIN_NOT_FOUND,
    DOMAIN_SERVICE_UNAVAILABLE, DOMAIN_VALIDATION, HTTP_BAD_JSON_BODY, HTTP_BAD_PATH_PARAM,
    HTTP_BAD_QUERY_PARAM, HTTP_BAD_REQUEST, HTTP_INTERNAL_ERROR, HTTP_PAYLOAD_TOO_LARGE,
    HTTP_REQUEST_TIMEOUT, HTTP_ROUTE_NOT_FOUND, HTTP_UNSUPPORTED_MEDIA_TYPE, ProblemCode,
};
use serde::Serialize;

/// Media type of every problem response (RFC 9457 §3).
pub const PROBLEM_CONTENT_TYPE: &str = "application/problem+json";

/// An RFC 9457 problem document (ADR-031 D1).
///
/// Every error response (status ≥ 400) produced by the API is an instance of
/// this document: `type` (derived from `code`), constant English `title`,
/// `status`, stable `code`, localized `detail` (English until Tranche 3), and
/// the `trace_id` extension for otel correlation.
#[derive(Debug, Clone, PartialEq, Serialize, utoipa::ToSchema)]
#[schema(
    example = json!({
        "type": "https://docs.breakdown.example/problems/scene.already-scheduled",
        "title": "Version conflict",
        "status": 409,
        "code": "concurrency.version-mismatch",
        "detail": "Version conflict",
        "trace_id": "4bf92f3577b34da6a3ce929d0e0e4736",
        "extensions": { "expected_version": 2, "current_version": 3 }
    })
)]
pub struct ProblemDetails {
    /// Dereferencable documentation anchor, derived from the `code`.
    #[serde(rename = "type")]
    #[schema(example = "https://docs.breakdown.example/problems/scene.already-scheduled")]
    pub type_: String,
    /// Constant English title (never localized; cacheable, spec-stable).
    pub title: String,
    /// Canonical HTTP status of this problem.
    #[schema(example = 409)]
    pub status: u16,
    /// Stable machine identity `{context}.{reason}` (the client contract).
    #[schema(example = "concurrency.version-mismatch")]
    pub code: String,
    /// Human-readable explanation; localized server-side (Tranche 3).
    #[schema(example = "Version conflict")]
    pub detail: String,
    /// W3C trace id of the request's otel span (support correlation).
    #[schema(example = "4bf92f3577b34da6a3ce929d0e0e4736")]
    pub trace_id: String,
    /// Declared S0/S1 extension fields, if any (ADR-031 D4).
    #[serde(skip_serializing_if = "Option::is_none")]
    pub extensions: Option<serde_json::Map<String, serde_json::Value>>,
}

impl IntoResponse for ProblemDetails {
    fn into_response(self) -> Response {
        let status = StatusCode::from_u16(self.status).unwrap_or(StatusCode::INTERNAL_SERVER_ERROR);
        let body = match serde_json::to_vec(&self) {
            Ok(body) => body,
            Err(error) => {
                // Unreachable in practice (plain strings + a JSON map); keep
                // the no-panic invariant with a static last resort.
                tracing::error!(%error, "failed to serialize problem document");
                return (status, [(header::CONTENT_TYPE, PROBLEM_CONTENT_TYPE)], "{}")
                    .into_response();
            }
        };
        (status, [(header::CONTENT_TYPE, PROBLEM_CONTENT_TYPE)], body).into_response()
    }
}

/// Builder for problem documents (ADR-031 D1: one builder for all sources).
///
/// Takes a registry entry directly, so an unregistered code cannot be emitted
/// (the registry is the only way to construct one).
#[derive(Debug)]
pub struct ProblemBuilder {
    code: ProblemCode,
    detail: Option<String>,
    extensions: Vec<(String, serde_json::Value)>,
}

impl ProblemBuilder {
    /// Start building a problem for a registered code.
    pub fn new(code: ProblemCode) -> Self {
        Self {
            code,
            detail: None,
            extensions: Vec::new(),
        }
    }

    /// Override the default `detail` (the constant English title).
    ///
    /// Tranche 3 replaces this with Fluent rendering; callers pass static
    /// localized-safe text only.
    pub fn detail(mut self, detail: impl Into<String>) -> Self {
        self.detail = Some(detail.into());
        self
    }

    /// Add a declared extension field (ADR-031 D4).
    ///
    /// Fields not declared in the code's registry whitelist are dropped with
    /// a loud error log — never emitted silently. Tranche 2 turns the
    /// whitelist into typed extension builders so undeclared fields fail
    /// compilation.
    pub fn extension(mut self, name: impl Into<String>, value: impl Serialize) -> Self {
        let name = name.into();
        if !self.code.extensions.contains(&name.as_str()) {
            tracing::error!(
                code = %self.code.code,
                field = %name,
                "problem extension field not declared for this code; dropped"
            );
            return self;
        }
        match serde_json::to_value(value) {
            Ok(value) => self.extensions.push((name, value)),
            Err(error) => tracing::error!(
                %error,
                field = %name,
                "extension value is not serializable; dropped"
            ),
        }
        self
    }

    /// Assemble the final problem document.
    pub fn build(self) -> ProblemDetails {
        let extensions = if self.extensions.is_empty() {
            None
        } else {
            let mut map = serde_json::Map::new();
            for (name, value) in self.extensions {
                map.insert(name, value);
            }
            Some(map)
        };
        ProblemDetails {
            type_: self.code.type_uri(),
            title: self.code.title.to_owned(),
            status: self.code.status,
            code: self.code.code.to_owned(),
            detail: self.detail.unwrap_or_else(|| self.code.title.to_owned()),
            trace_id: current_trace_id(),
            extensions,
        }
    }
}

/// Convenience constructor for [`ProblemBuilder`].
pub fn problem(code: ProblemCode) -> ProblemBuilder {
    ProblemBuilder::new(code)
}

/// The W3C trace id of the current otel span, or a fresh random id when no
/// otel layer is installed (local dev / tests).
///
/// The http-error-surface contract requires a non-empty hex `trace_id` on
/// every problem; when tracing is not bridged to otel there is no server
/// trace id to mirror, so we emit a fresh id and keep the contract stable.
pub fn current_trace_id() -> String {
    use opentelemetry::trace::TraceContextExt as _;
    use tracing_opentelemetry::OpenTelemetrySpanExt as _;

    let context = tracing::Span::current().context();
    let span = context.span();
    let span_context = span.span_context();
    if span_context.is_valid() {
        span_context.trace_id().to_string()
    } else {
        uuid::Uuid::now_v7().to_string().replace('-', "")
    }
}

/// Map a `DomainError` to its problem document (ADR-031 D6).
///
/// The orphan rule forbids a direct `IntoResponse for DomainError` impl in
/// this crate (`DomainError` lives in `core`), so the mapping lives behind
/// [`ApiError::Domain`] — the single `IntoResponse` at the HTTP boundary.
///
/// Tranche 1 uses generic per-variant codes with the constant English title
/// as `detail`; Tranche 2 registers per-aggregate codes with typed
/// extensions, Tranche 3 localizes `detail`.
fn domain_error_problem(err: DomainError) -> ProblemDetails {
    match err {
        DomainError::NotFound(_) => problem(DOMAIN_NOT_FOUND).build(),
        DomainError::Unauthorized(_) => problem(DOMAIN_FORBIDDEN).build(),
        DomainError::ValidationError(_) => problem(DOMAIN_VALIDATION).build(),
        DomainError::Conflict(_) => problem(DOMAIN_CONFLICT).build(),
        DomainError::ServiceUnavailable(_) => problem(DOMAIN_SERVICE_UNAVAILABLE).build(),
        DomainError::VersionConflict {
            expected, current, ..
        } => problem(CONCURRENCY_VERSION_MISMATCH)
            .extension("expected_version", expected)
            .extension("current_version", current)
            .build(),
    }
}

// ---------------------------------------------------------------------------
// ApiError — the handler error type.
// ---------------------------------------------------------------------------

/// Error type returned by API handlers (ADR-031).
///
/// Handlers return `Result<_, ApiError>` and propagate domain failures with
/// `?` (via [`From<DomainError>`]); the status/code/detail mapping is
/// centralized here through the registry — no per-handler status mapping.
#[derive(Debug)]
pub enum ApiError {
    /// Domain failure, mapped through the registry.
    Domain(DomainError),
    /// Handler-internal authorization gate denial → 403 `domain.forbidden`.
    Forbidden(&'static str),
    /// Malformed request (path/body mismatch, bad headers) → 400 `http.bad-request`.
    BadRequest(&'static str),
    /// Malformed JSON body → 400 `http.bad-json-body`.
    BadJsonBody(&'static str),
    /// Domain validation failure → 422 `domain.validation` (RFC 9110 §15.5.21).
    Validation(&'static str),
    /// Invalid path parameter → 400 `http.bad-path-param`.
    BadPathParam(&'static str),
    /// Invalid/absent required query parameter → 400 `http.bad-query-param`.
    BadQueryParam(&'static str),
    /// 404 `domain.not-found` (incl. deliberately hidden per the oracle policy).
    NotFound(&'static str),
    /// 409 `domain.conflict`.
    Conflict(&'static str),
    /// 503 `domain.service-unavailable`.
    ServiceUnavailable(&'static str),
    /// 415 `http.unsupported-media-type`.
    UnsupportedMediaType(&'static str),
    /// 413 `http.payload-too-large`.
    PayloadTooLarge(&'static str),
    /// 500 `http.internal-error` — `detail` is always static text; the real
    /// error must be logged by the caller (internal text never leaves the
    /// server, ADR-031 decision 6).
    Internal,
    /// Report renderer failure, mapped via the registry (typed codes in
    /// Tranche 2).
    ReportRender(breakdown_core::reporting::ReportRenderError),
}

impl From<DomainError> for ApiError {
    fn from(err: DomainError) -> Self {
        ApiError::Domain(err)
    }
}

impl ApiError {
    /// Render this error as a problem document — the single envelope path
    /// used by [`IntoResponse`] (ADR-031 D1). Exposed so tests and
    /// middleware can assert on the document without response parsing.
    pub fn into_problem(self) -> ProblemDetails {
        match self {
            ApiError::Domain(err) => domain_error_problem(err),
            ApiError::Forbidden(msg) => problem(DOMAIN_FORBIDDEN).detail(msg).build(),
            ApiError::BadRequest(msg) => problem(HTTP_BAD_REQUEST).detail(msg).build(),
            ApiError::BadJsonBody(msg) => problem(HTTP_BAD_JSON_BODY).detail(msg).build(),
            ApiError::Validation(msg) => problem(DOMAIN_VALIDATION).detail(msg).build(),
            ApiError::BadPathParam(msg) => problem(HTTP_BAD_PATH_PARAM).detail(msg).build(),
            ApiError::BadQueryParam(msg) => problem(HTTP_BAD_QUERY_PARAM).detail(msg).build(),
            ApiError::NotFound(msg) => problem(DOMAIN_NOT_FOUND).detail(msg).build(),
            ApiError::Conflict(msg) => problem(DOMAIN_CONFLICT).detail(msg).build(),
            ApiError::ServiceUnavailable(msg) => {
                problem(DOMAIN_SERVICE_UNAVAILABLE).detail(msg).build()
            }
            ApiError::UnsupportedMediaType(msg) => {
                problem(HTTP_UNSUPPORTED_MEDIA_TYPE).detail(msg).build()
            }
            ApiError::PayloadTooLarge(msg) => problem(HTTP_PAYLOAD_TOO_LARGE).detail(msg).build(),
            ApiError::Internal => problem(HTTP_INTERNAL_ERROR).build(),
            ApiError::ReportRender(err) => report_render_problem(err),
        }
    }
}

impl IntoResponse for ApiError {
    fn into_response(self) -> Response {
        self.into_problem().into_response()
    }
}

fn report_render_problem(err: breakdown_core::reporting::ReportRenderError) -> ProblemDetails {
    use breakdown_core::reporting::ReportRenderError;
    match &err {
        ReportRenderError::PageLimitExceeded { .. }
        | ReportRenderError::InputBoundsExceeded { .. } => problem(DOMAIN_VALIDATION)
            .detail("Report exceeds the configured limits")
            .build(),
        ReportRenderError::RenderTimeout => problem(HTTP_REQUEST_TIMEOUT).build(),
        other => {
            tracing::error!(error = %other, "report rendering failed");
            problem(HTTP_INTERNAL_ERROR).build()
        }
    }
}

// ---------------------------------------------------------------------------
// Extractor rejection wrappers (ADR-031 D3).
//
// The handlers import these in place of the plain axum extractors so that
// framework rejections (bad JSON, bad path/query params, body limits) become
// problem documents instead of plain text.
// ---------------------------------------------------------------------------

/// Wrapper around `axum::Json` with a problem-document rejection.
///
/// Collects the (limited) body itself so that body-limit failures can be
/// classified as `http.payload-too-large` (the wrapped axum rejection hides
/// `LengthLimitError` inside a `Box<dyn Error>`); otherwise mirrors axum's
/// content-type gate and `serde_json` deserialization.
#[derive(Debug)]
pub struct Json<T>(pub T);

impl<T, S> axum::extract::FromRequest<S> for Json<T>
where
    T: serde::de::DeserializeOwned,
    S: Send + Sync,
{
    type Rejection = ApiError;

    async fn from_request(
        req: axum::http::Request<axum::body::Body>,
        _state: &S,
    ) -> Result<Self, Self::Rejection> {
        use axum::RequestExt as _;
        use http_body_util::BodyExt as _;

        if !is_json_content_type(req.headers()) {
            return Err(ApiError::UnsupportedMediaType("missing JSON content type"));
        }
        let bytes = match req.into_limited_body().collect().await {
            Ok(collected) => collected.to_bytes(),
            Err(error) => {
                if error
                    .into_inner()
                    .downcast_ref::<http_body_util::LengthLimitError>()
                    .is_some()
                {
                    return Err(ApiError::PayloadTooLarge(
                        "request body exceeds the size limit",
                    ));
                }
                return Err(ApiError::BadJsonBody("failed to read request body"));
            }
        };
        match serde_json::from_slice::<T>(&bytes) {
            Ok(value) => Ok(Json(value)),
            Err(error) if error.is_syntax() => {
                Err(ApiError::BadJsonBody("malformed JSON request body"))
            }
            Err(_) => Err(ApiError::Validation(
                "request body does not match the expected schema",
            )),
        }
    }
}

impl<T> IntoResponse for Json<T>
where
    T: Serialize,
{
    fn into_response(self) -> Response {
        axum::Json(self.0).into_response()
    }
}

/// `application/json` or `application/*+json` (mirrors axum's gate).
fn is_json_content_type(headers: &axum::http::HeaderMap) -> bool {
    let Some(content_type) = headers
        .get(header::CONTENT_TYPE)
        .and_then(|value| value.to_str().ok())
    else {
        return false;
    };
    let mime = content_type.split(';').next().unwrap_or("").trim();
    mime == "application/json" || mime.ends_with("+json")
}

/// Wrapper around `axum::extract::Path` with a problem-document rejection.
#[derive(Debug)]
pub struct Path<T>(pub T);

impl<T, S> axum::extract::FromRequestParts<S> for Path<T>
where
    T: serde::de::DeserializeOwned + Send,
    S: Send + Sync,
{
    type Rejection = ApiError;

    async fn from_request_parts(parts: &mut Parts, state: &S) -> Result<Self, Self::Rejection> {
        match axum::extract::Path::<T>::from_request_parts(parts, state).await {
            Ok(axum::extract::Path(value)) => Ok(Path(value)),
            Err(_) => Err(ApiError::BadPathParam("invalid path parameter")),
        }
    }
}

/// Wrapper around `axum::extract::Query` with a problem-document rejection.
#[derive(Debug)]
pub struct Query<T>(pub T);

impl<T, S> axum::extract::FromRequestParts<S> for Query<T>
where
    T: serde::de::DeserializeOwned + Send,
    S: Send + Sync,
{
    type Rejection = ApiError;

    async fn from_request_parts(parts: &mut Parts, state: &S) -> Result<Self, Self::Rejection> {
        match axum::extract::Query::<T>::from_request_parts(parts, state).await {
            Ok(axum::extract::Query(value)) => Ok(Query(value)),
            Err(_) => Err(ApiError::BadQueryParam("invalid query parameter")),
        }
    }
}

/// Wrapper around `axum::body::Bytes` with a problem-document rejection
/// (body-size limits surface as `http.payload-too-large`, not plain text).
#[repr(transparent)]
#[derive(Debug)]
pub struct Bytes(pub AxumBytes);

impl std::ops::Deref for Bytes {
    type Target = AxumBytes;

    fn deref(&self) -> &Self::Target {
        &self.0
    }
}

impl From<Bytes> for AxumBytes {
    fn from(value: Bytes) -> Self {
        value.0
    }
}

impl<S> axum::extract::FromRequest<S> for Bytes
where
    S: Send + Sync,
{
    type Rejection = ApiError;

    async fn from_request(
        req: axum::http::Request<axum::body::Body>,
        _state: &S,
    ) -> Result<Self, Self::Rejection> {
        use axum::RequestExt as _;
        use http_body_util::BodyExt as _;

        match req.into_limited_body().collect().await {
            Ok(collected) => Ok(Bytes(collected.to_bytes())),
            Err(error) => {
                if error
                    .into_inner()
                    .downcast_ref::<http_body_util::LengthLimitError>()
                    .is_some()
                {
                    Err(ApiError::PayloadTooLarge(
                        "request body exceeds the size limit",
                    ))
                } else {
                    Err(ApiError::BadRequest("failed to read request body"))
                }
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Fallback / panic catch-all (ADR-031 D3).
// ---------------------------------------------------------------------------

/// Fallback handler for unknown routes → 404 `http.route-not-found`.
///
/// Wired as `Router::fallback` in `crates/api/src/routes/mod.rs`.
pub async fn route_not_found() -> ProblemDetails {
    problem(HTTP_ROUTE_NOT_FOUND).build()
}

/// Response for unhandled panics (wired via `tower-http` `CatchPanicLayer`).
///
/// Always a static `http.internal-error` problem: no internal error text, no
/// stack trace, no data values — plus the request's `trace_id` (ADR-031
/// decision 6, http-error-surface spec).
pub fn panic_response(_panic: Box<dyn std::any::Any + Send>) -> Response {
    tracing::error!("unhandled panic caught by CatchPanicLayer");
    problem(HTTP_INTERNAL_ERROR).build().into_response()
}

#[cfg(test)]
mod tests {
    use super::*;
    use breakdown_core::error_registry::HTTP_BAD_JSON_BODY;

    #[test]
    fn problem_envelope_matches_rfc_9457_shape() {
        let document = problem(CONCURRENCY_VERSION_MISMATCH)
            .extension("expected_version", 2u64)
            .extension("current_version", 3u64)
            .build();

        assert_eq!(document.status, 409);
        assert_eq!(document.code, "concurrency.version-mismatch");
        assert_eq!(document.title, "Version conflict");
        assert_eq!(
            document.type_,
            "https://docs.breakdown.example/problems/concurrency.version-mismatch"
        );
        assert_eq!(document.detail, "Version conflict");

        let value: serde_json::Value = serde_json::to_value(&document).expect("serializable");
        assert_eq!(value["type"], document.type_);
        assert_eq!(value["title"], "Version conflict");
        assert_eq!(value["status"], 409);
        assert_eq!(value["code"], "concurrency.version-mismatch");
        assert_eq!(value["extensions"]["expected_version"], 2);
        assert_eq!(value["extensions"]["current_version"], 3);
        // trace_id must be a non-empty hex string (http-error-surface spec).
        let trace_id = value["trace_id"].as_str().expect("trace_id present");
        assert_eq!(trace_id.len(), 32);
        assert!(trace_id.chars().all(|c| c.is_ascii_hexdigit()));
    }

    #[test]
    fn code_without_extensions_omits_the_member() {
        let document = problem(HTTP_BAD_JSON_BODY).build();
        let value = serde_json::to_value(&document).expect("serializable");
        assert!(value.get("extensions").is_none());
    }

    #[test]
    fn undeclared_extension_field_is_dropped() {
        let document = problem(HTTP_BAD_JSON_BODY)
            .extension("not_declared", 42u64)
            .build();
        assert!(document.extensions.is_none());
    }

    #[test]
    fn problem_response_sets_content_type_and_status() {
        let response = problem(DOMAIN_NOT_FOUND).build().into_response();
        assert_eq!(response.status(), StatusCode::NOT_FOUND);
        assert_eq!(
            response.headers().get(header::CONTENT_TYPE).unwrap(),
            PROBLEM_CONTENT_TYPE
        );
    }

    #[test]
    fn trace_id_is_non_empty_hex_even_without_otel() {
        let id = current_trace_id();
        assert_eq!(id.len(), 32);
        assert!(id.chars().all(|c| c.is_ascii_hexdigit()));
    }

    #[test]
    fn domain_error_mapping_uses_generic_tranche1_codes() {
        let response = ApiError::from(DomainError::NotFound("Character".into())).into_response();
        assert_eq!(response.status(), StatusCode::NOT_FOUND);
        let response = ApiError::from(DomainError::ValidationError("x".into())).into_response();
        assert_eq!(response.status(), StatusCode::UNPROCESSABLE_ENTITY);
        let response = ApiError::from(DomainError::Unauthorized("x".into())).into_response();
        assert_eq!(response.status(), StatusCode::FORBIDDEN);
        let response = ApiError::from(DomainError::Conflict("x".into())).into_response();
        assert_eq!(response.status(), StatusCode::CONFLICT);
        let response = ApiError::from(DomainError::ServiceUnavailable("x".into())).into_response();
        assert_eq!(response.status(), StatusCode::SERVICE_UNAVAILABLE);
    }

    #[test]
    fn version_conflict_carries_typed_extensions() {
        let response = ApiError::from(DomainError::VersionConflict {
            entity: "Season".into(),
            expected: breakdown_core::shared::AggregateVersion(2),
            current: breakdown_core::shared::AggregateVersion(3),
        })
        .into_response();
        assert_eq!(response.status(), StatusCode::CONFLICT);
    }

    #[test]
    fn api_error_ad_hoc_variants_map_to_expected_statuses() {
        assert_eq!(
            ApiError::Forbidden("x").into_response().status(),
            StatusCode::FORBIDDEN
        );
        assert_eq!(
            ApiError::BadRequest("x").into_response().status(),
            StatusCode::BAD_REQUEST
        );
        assert_eq!(
            ApiError::BadPathParam("x").into_response().status(),
            StatusCode::BAD_REQUEST
        );
        assert_eq!(
            ApiError::BadQueryParam("x").into_response().status(),
            StatusCode::BAD_REQUEST
        );
        assert_eq!(
            ApiError::NotFound("x").into_response().status(),
            StatusCode::NOT_FOUND
        );
        assert_eq!(
            ApiError::Conflict("x").into_response().status(),
            StatusCode::CONFLICT
        );
        assert_eq!(
            ApiError::ServiceUnavailable("x").into_response().status(),
            StatusCode::SERVICE_UNAVAILABLE
        );
        assert_eq!(
            ApiError::UnsupportedMediaType("x").into_response().status(),
            StatusCode::UNSUPPORTED_MEDIA_TYPE
        );
        assert_eq!(
            ApiError::PayloadTooLarge("x").into_response().status(),
            StatusCode::PAYLOAD_TOO_LARGE
        );
        assert_eq!(
            ApiError::Internal.into_response().status(),
            StatusCode::INTERNAL_SERVER_ERROR
        );
    }
}
