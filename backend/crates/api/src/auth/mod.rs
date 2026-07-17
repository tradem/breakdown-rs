// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors

//! OIDC authentication for the API layer (Decision D1, D2, D5).
//!
//! `core` must stay free of any OIDC/HTTP concern (ADR-017); everything in
//! this module lives in `api`. The [`AuthLayer`] validates the bearer token's
//! signature, `iss`, `aud`, and `exp` against the IdP JWKS and inserts a
//! [`CurrentUser`] into the request extensions. [`ActiveBlock`] (Decision D2)
//! parses the `X-Active-Block` header for the authorization layer.

pub mod authorization;
pub mod jwks;

pub use authorization::{AuthorizationState, authorize_middleware};
pub use jwks::{CachingJwksProvider, JwksError, JwksProvider, StaticJwksProvider};

use std::collections::HashMap;
use std::sync::Arc;

use axum::extract::{FromRequestParts, Request, State};
use axum::http::{StatusCode, header::AUTHORIZATION, request::Parts};
use axum::middleware::Next;
use axum::response::{IntoResponse, Response};
use breakdown_core::shared::{BlockId, UserId};
use jsonwebtoken::{Algorithm, DecodingKey, Validation, decode, decode_header};
use serde::Deserialize;
use uuid::Uuid;

/// The authenticated principal, attached to request extensions by [`AuthLayer`].
///
/// `sub` is the opaque OIDC subject wrapped as a `UserId` (ADR-010); `core`
/// never decodes or stores further identity attributes.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct CurrentUser {
    /// OIDC `sub` claim, wrapped as an opaque `UserId`.
    pub sub: UserId,
    /// OIDC `email` claim, if present.
    pub email: Option<String>,
}

impl CurrentUser {
    /// Build a dummy user (dev mode / tests). Never used in production paths.
    pub fn dummy(sub: impl Into<String>) -> Self {
        Self {
            sub: UserId::from_sub(sub),
            email: None,
        }
    }

    /// Build a dummy user with an email (dev mode / tests).
    pub fn dummy_with_email(sub: impl Into<String>, email: impl Into<String>) -> Self {
        Self {
            sub: UserId::from_sub(sub),
            email: Some(email.into()),
        }
    }
}

impl<S> FromRequestParts<S> for CurrentUser
where
    S: Send + Sync,
{
    type Rejection = AuthError;

    async fn from_request_parts(parts: &mut Parts, _state: &S) -> Result<Self, Self::Rejection> {
        parts
            .extensions
            .get::<CurrentUser>()
            .cloned()
            .ok_or(AuthError::Unauthorized)
    }
}

/// The block the caller is currently acting in (Decision D2).
///
/// Conveyed by the `X-Active-Block` request header and parsed into a
/// [`BlockId`]. Missing or malformed values are rejected with `400` (the
/// authorization layer treats a missing active block on a block-scoped request
/// as a client error, never as a server failure).
pub struct ActiveBlock(pub BlockId);

impl<S> FromRequestParts<S> for ActiveBlock
where
    S: Send + Sync,
{
    type Rejection = AuthError;

    async fn from_request_parts(parts: &mut Parts, _state: &S) -> Result<Self, Self::Rejection> {
        let header = parts
            .headers
            .get("x-active-block")
            .and_then(|v| v.to_str().ok())
            .ok_or(AuthError::MissingActiveBlock)?;
        let uuid = Uuid::parse_str(header).map_err(|_| AuthError::InvalidActiveBlock)?;
        Ok(ActiveBlock(BlockId::from_uuid(uuid)))
    }
}

/// OIDC issuer configuration, sourced from the environment (Section 4.6).
#[derive(Clone, Debug)]
pub struct OidcConfig {
    /// Expected `iss` claim (the IdP issuer URL).
    pub iss: String,
    /// Expected `aud` claim (the resource indicator for this API).
    pub audience: String,
    /// JWKS document URL used to fetch signing keys.
    pub jwks_url: String,
    /// Signing algorithm (RS256 for standard OIDC).
    pub algorithm: Algorithm,
}

impl OidcConfig {
    /// Build the config from `OIDC_ISS` / `OIDC_AUDIENCE` / `OIDC_JWKS_URL`.
    ///
    /// Fails if any required variable is missing — production must be explicit.
    pub fn from_env() -> Result<Self, String> {
        let iss = std::env::var("OIDC_ISS").map_err(|_| "OIDC_ISS not set".to_string())?;
        let audience =
            std::env::var("OIDC_AUDIENCE").map_err(|_| "OIDC_AUDIENCE not set".to_string())?;
        let jwks_url =
            std::env::var("OIDC_JWKS_URL").map_err(|_| "OIDC_JWKS_URL not set".to_string())?;
        Ok(Self {
            iss,
            audience,
            jwks_url,
            algorithm: Algorithm::RS256,
        })
    }
}

/// Shared authentication state for the [`AuthLayer`].
///
/// Held behind `Arc` so it can be supplied to the middleware via
/// `axum::middleware::from_fn_with_state`.
#[derive(Clone)]
pub struct AuthState {
    config: OidcConfig,
    jwks: Arc<dyn JwksProvider>,
    /// When `Some`, the layer short-circuits to this user without verifying a
    /// token (dev mode / tests only — never constructed on the production path).
    dev_override: Option<CurrentUser>,
}

impl AuthState {
    /// Production state: verify tokens against `config` using `jwks`.
    pub fn new(config: OidcConfig, jwks: Arc<dyn JwksProvider>) -> Self {
        Self {
            config,
            jwks,
            dev_override: None,
        }
    }

    /// Dev-mode state: skip token verification and inject `user`. Used by unit
    /// and integration tests and local dev. `main.rs` never calls this.
    pub fn dev(user: CurrentUser) -> Self {
        Self {
            config: OidcConfig {
                iss: String::new(),
                audience: String::new(),
                jwks_url: String::new(),
                algorithm: Algorithm::RS256,
            },
            jwks: Arc::new(StaticJwksProvider::new(HashMap::new())),
            dev_override: Some(user),
        }
    }

    /// Whether this state runs in dev-override mode (no real verification).
    pub fn is_dev(&self) -> bool {
        self.dev_override.is_some()
    }

    /// Build the production auth state from the environment, or fall back to
    /// dev mode when `OIDC_ISS` is absent and `DEV_AUTH_SUB` is set.
    ///
    /// Fails only if neither real OIDC config nor a dev subject is available.
    /// Production never sets `DEV_AUTH_SUB`, so dev mode can never be entered
    /// there.
    pub fn from_env_or_dev() -> Result<Self, String> {
        match OidcConfig::from_env() {
            Ok(cfg) => {
                let jwks: Arc<dyn JwksProvider> = Arc::new(CachingJwksProvider::new(
                    cfg.jwks_url.clone(),
                    reqwest::Client::new(),
                    std::time::Duration::from_secs(3600),
                ));
                Ok(AuthState::new(cfg, jwks))
            }
            Err(_) => match std::env::var("DEV_AUTH_SUB") {
                Ok(sub) => {
                    let email = std::env::var("DEV_AUTH_EMAIL").unwrap_or_default();
                    let user = if email.is_empty() {
                        CurrentUser::dummy(sub)
                    } else {
                        CurrentUser::dummy_with_email(sub, email)
                    };
                    Ok(AuthState::dev(user))
                }
                Err(_) => Err(
                    "OIDC_ISS/OIDC_AUDIENCE/OIDC_JWKS_URL not set and DEV_AUTH_SUB not set"
                        .to_string(),
                ),
            },
        }
    }
}

/// Authentication failures surfaced as HTTP responses.
#[derive(Debug)]
pub enum AuthError {
    /// Missing/invalid token, or signature/claim validation failure → `401`.
    Unauthorized,
    /// `X-Active-Block` header missing → `400`.
    MissingActiveBlock,
    /// `X-Active-Block` header present but not a valid `BlockId` → `400`.
    InvalidActiveBlock,
    /// JWKS could not be fetched/parsed → `503`.
    JwksUnavailable,
}

impl IntoResponse for AuthError {
    fn into_response(self) -> Response {
        let (status, message) = match self {
            AuthError::Unauthorized => (StatusCode::UNAUTHORIZED, "unauthorized"),
            AuthError::MissingActiveBlock => {
                (StatusCode::BAD_REQUEST, "missing X-Active-Block header")
            }
            AuthError::InvalidActiveBlock => {
                (StatusCode::BAD_REQUEST, "invalid X-Active-Block header")
            }
            AuthError::JwksUnavailable => (
                StatusCode::SERVICE_UNAVAILABLE,
                "identity provider unavailable",
            ),
        };
        (
            status,
            axum::Json(serde_json::json!({ "message": message })),
        )
            .into_response()
    }
}

/// Claims we extract and validate from the bearer token.
///
/// `iss`/`aud`/`exp` are enforced by `jsonwebtoken::Validation` (which
/// reads them directly from the token), so the deserialized `Claims` only
/// needs the fields the handler actually consumes (`sub`, `email`).
#[derive(Debug, Deserialize)]
struct Claims {
    sub: String,
    #[serde(default)]
    email: Option<String>,
}

/// Axum middleware implementing the `AuthLayer` (Decision D1).
///
/// Runs first (outermost). In dev-override mode it injects the dummy user and
/// returns immediately. Otherwise it extracts the bearer token, resolves the
/// matching decoding key by `kid`, validates `iss`/`aud`/`exp`/signature, and
/// on success inserts a [`CurrentUser`]. Failures map to `401` (client auth
/// problem) or `503` (JWKS unavailable — an IdP/backend failure, not the
/// client's).
pub async fn auth_middleware(
    State(state): State<Arc<AuthState>>,
    mut req: Request,
    next: Next,
) -> Response {
    let path = req.uri().path().to_string();
    // Documentation endpoints are public.
    if path.starts_with("/swagger-ui") || path.starts_with("/api-docs") {
        return next.run(req).await;
    }

    // Dev mode: bypass verification entirely.
    if let Some(user) = &state.dev_override {
        req.extensions_mut().insert(user.clone());
        return next.run(req).await;
    }

    let token = match bearer_token(req.headers().get(AUTHORIZATION)) {
        Some(t) => t,
        None => return AuthError::Unauthorized.into_response(),
    };

    // Resolve the key by `kid` from the (cached) JWKS.
    let header = match decode_header(&token) {
        Ok(h) => h,
        Err(_) => return AuthError::Unauthorized.into_response(),
    };
    let keys = match state.jwks.decoding_keys().await {
        Ok(k) => k,
        Err(_) => return AuthError::JwksUnavailable.into_response(),
    };
    let key: &DecodingKey = match header.kid.as_deref().and_then(|kid| keys.get(kid)) {
        Some(k) => k,
        None => return AuthError::Unauthorized.into_response(),
    };

    let mut validation = Validation::new(state.config.algorithm);
    validation.set_issuer(&[state.config.iss.as_str()]);
    validation.set_audience(&[state.config.audience.as_str()]);
    validation.validate_exp = true;

    let data = match decode::<Claims>(&token, key, &validation) {
        Ok(d) => d,
        Err(_) => return AuthError::Unauthorized.into_response(),
    };

    req.extensions_mut().insert(CurrentUser {
        sub: UserId::from_sub(data.claims.sub),
        email: data.claims.email,
    });

    next.run(req).await
}

/// Extract a non-empty bearer token from an `Authorization` header value.
fn bearer_token(header: Option<&axum::http::HeaderValue>) -> Option<String> {
    let value = header?.to_str().ok()?;
    let token = value.strip_prefix("Bearer ")?;
    if token.is_empty() {
        return None;
    }
    Some(token.to_string())
}

#[cfg(test)]
mod tests {
    use std::collections::HashMap;
    use std::sync::Arc;

    use axum::http::HeaderValue;

    use super::*;

    #[test]
    fn is_dev_reflects_override() {
        assert!(AuthState::dev(CurrentUser::dummy("x")).is_dev());
        let prod = AuthState::new(
            OidcConfig {
                iss: "https://iss".into(),
                audience: "aud".into(),
                jwks_url: "https://iss/.well-known/jwks".into(),
                algorithm: jsonwebtoken::Algorithm::RS256,
            },
            Arc::new(StaticJwksProvider::new(HashMap::new())),
        );
        assert!(!prod.is_dev());
    }

    #[test]
    fn bearer_token_parses_prefixed_header() {
        assert_eq!(
            bearer_token(Some(&HeaderValue::from_static("Bearer tok-123"))),
            Some("tok-123".to_string())
        );
        assert_eq!(
            bearer_token(Some(&HeaderValue::from_static("Basic abc"))),
            None
        );
        assert_eq!(
            bearer_token(Some(&HeaderValue::from_static("Bearer "))),
            None
        );
        assert_eq!(bearer_token(None), None);
    }
}
