// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors

//! OIDC JWKS discovery behind an injectable `JwksProvider` (Decision D1).
//!
//! `core` must stay free of any OIDC/HTTP dependency (ADR-017), so the
//! provider trait lives in `api` together with its concrete implementations.
//! Tests inject a [`StaticJwksProvider`]; production uses
//! [`CachingJwksProvider`], which fetches the IdP JWKS document, caches it for
//! a short TTL, and refreshes on miss or on a validation failure.

use std::collections::HashMap;
use std::sync::Arc;
use std::time::{Duration, Instant};

use async_trait::async_trait;
use base64::Engine;
use jsonwebtoken::DecodingKey;
use serde::Deserialize;
use thiserror::Error;
use tokio::sync::RwLock;

/// Errors that can occur while resolving decoding keys from a JWKS document.
#[derive(Debug, Error)]
pub enum JwksError {
    /// The JWKS endpoint could not be reached or returned a transport error.
    #[error("JWKS fetch failed: {0}")]
    Fetch(String),
    /// The JWKS document was malformed or contained no usable RSA key.
    #[error("JWKS parse failed: {0}")]
    Parse(String),
}

/// Resolves the set of `(kid, DecodingKey)` used to verify OIDC tokens.
///
/// Implemented as a trait so unit tests can inject a static key set without
/// touching the network (Decision D1).
#[async_trait]
pub trait JwksProvider: Send + Sync {
    /// Return the current decoding keys, keyed by JWK `kid`.
    async fn decoding_keys(&self) -> Result<HashMap<String, DecodingKey>, JwksError>;
}

/// A fixed key set, used by tests and the dev-mode dummy verifier.
#[derive(Clone, Default)]
pub struct StaticJwksProvider {
    keys: HashMap<String, DecodingKey>,
}

impl StaticJwksProvider {
    /// Build a static provider from a `kid -> DecodingKey` map.
    pub fn new(keys: HashMap<String, DecodingKey>) -> Self {
        Self { keys }
    }
}

#[async_trait]
impl JwksProvider for StaticJwksProvider {
    async fn decoding_keys(&self) -> Result<HashMap<String, DecodingKey>, JwksError> {
        Ok(self.keys.clone())
    }
}

/// Fetches and caches the IdP JWKS document (production implementation).
///
/// The cache is held behind a `tokio::sync::RwLock`; reads are served from
/// cache while fresh, otherwise a fetch refreshes it. A fetch/parse failure is
/// surfaced to the caller so the auth middleware can respond `503`.
pub struct CachingJwksProvider {
    jwks_url: String,
    http: reqwest::Client,
    cache: RwLock<Option<CachedKeys>>,
    ttl: Duration,
}

struct CachedKeys {
    keys: HashMap<String, DecodingKey>,
    fetched_at: Instant,
}

impl CachingJwksProvider {
    /// Create a provider for `jwks_url` using `http` to fetch, caching for `ttl`.
    pub fn new(jwks_url: impl Into<String>, http: reqwest::Client, ttl: Duration) -> Self {
        Self {
            jwks_url: jwks_url.into(),
            http,
            cache: RwLock::new(None),
            ttl,
        }
    }
}

#[async_trait]
impl JwksProvider for CachingJwksProvider {
    async fn decoding_keys(&self) -> Result<HashMap<String, DecodingKey>, JwksError> {
        // Fast path: serve a fresh cached set.
        {
            let guard = self.cache.read().await;
            if let Some(cached) = guard.as_ref()
                && cached.fetched_at.elapsed() < self.ttl
            {
                return Ok(cached.keys.clone());
            }
        }

        // Refresh on miss or expiry.
        let body = self
            .http
            .get(&self.jwks_url)
            .send()
            .await
            .map_err(|e| JwksError::Fetch(e.to_string()))?
            .text()
            .await
            .map_err(|e| JwksError::Fetch(e.to_string()))?;

        let jwks: Jwks =
            serde_json::from_str(&body).map_err(|e| JwksError::Parse(e.to_string()))?;

        let mut keys = HashMap::new();
        for jwk in jwks.keys {
            // Only RSA signing keys participate in verification.
            if jwk.kty != "RSA" || jwk.use_.as_deref() == Some("enc") {
                continue;
            }
            let kid = match jwk.kid {
                Some(k) => k,
                None => continue,
            };
            // JWK `n`/`e` are base64url; `DecodingKey::from_rsa_components`
            // expects standard base64, so normalize before handing over.
            let n = normalize_b64(&jwk.n);
            let e = normalize_b64(&jwk.e);
            let key = DecodingKey::from_rsa_components(&n, &e)
                .map_err(|err| JwksError::Parse(err.to_string()))?;
            keys.insert(kid, key);
        }

        if keys.is_empty() {
            return Err(JwksError::Parse("no usable RSA key in JWKS".into()));
        }

        *self.cache.write().await = Some(CachedKeys {
            keys: keys.clone(),
            fetched_at: Instant::now(),
        });
        Ok(keys)
    }
}

/// Decode a base64url (or standard) string and re-encode it as standard
/// base64, so it can be consumed by `DecodingKey::from_rsa_components`.
fn normalize_b64(s: &str) -> String {
    let bytes = base64::engine::general_purpose::URL_SAFE_NO_PAD
        .decode(s)
        .or_else(|_| base64::engine::general_purpose::STANDARD.decode(s))
        .unwrap_or_default();
    base64::engine::general_purpose::STANDARD.encode(bytes)
}

#[derive(Debug, Deserialize)]
struct Jwks {
    keys: Vec<Jwk>,
}

#[derive(Debug, Deserialize)]
struct Jwk {
    #[serde(default)]
    kty: String,
    #[serde(default)]
    kid: Option<String>,
    #[serde(default)]
    n: String,
    #[serde(default)]
    e: String,
    #[serde(default, rename = "use")]
    use_: Option<String>,
}

/// Shared helper: build an `Arc<dyn JwksProvider>` from a static key set.
pub fn static_provider(keys: HashMap<String, DecodingKey>) -> Arc<dyn JwksProvider> {
    Arc::new(StaticJwksProvider::new(keys))
}

#[cfg(test)]
#[path = "jwks_test.rs"]
mod tests;
