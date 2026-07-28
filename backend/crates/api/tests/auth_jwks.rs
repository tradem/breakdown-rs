// SPDX-License-Identifier: AGPL-3.0
use api::auth::JwksProvider;
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: mimo-v2.5 (opencode-go)

use api::auth::jwks::{CachingJwksProvider, StaticJwksProvider, normalize_b64};
use jsonwebtoken::DecodingKey;
use std::collections::HashMap;
use std::time::Duration;

#[tokio::test]
async fn static_provider_returns_configured_keys() {
    let mut map = HashMap::new();
    map.insert("k1".to_string(), DecodingKey::from_secret(b"secret"));
    let provider = StaticJwksProvider::new(map);
    let keys = provider.decoding_keys().await.unwrap();
    assert_eq!(keys.len(), 1);
    assert!(keys.contains_key("k1"));
}

#[tokio::test]
async fn caching_provider_errors_on_unreachable() {
    // An unreachable JWKS URL must surface as an error (not an empty set),
    // so a deployment with a broken IdP fails closed to `503`.
    let provider = CachingJwksProvider::new(
        "http://127.0.0.1:1/.well-known/jwks",
        reqwest::Client::new(),
        Duration::from_secs(3600),
    );
    assert!(provider.decoding_keys().await.is_err());
}

#[tokio::test]
async fn caching_provider_returns_empty_on_empty_jwks() {
    // A JWKS with no keys must produce a Parse error
    // (exercises the `if keys.is_empty()` return path).
    let jwks = serde_json::json!({ "keys": [] });

    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap();
    let url = format!("http://{addr}/.well-known/jwks");

    let app = axum::Router::new().route(
        "/.well-known/jwks",
        axum::routing::get(|| async move { axum::Json(jwks) }),
    );

    tokio::spawn(async move {
        axum::serve(listener, app.into_make_service())
            .await
            .unwrap();
    });

    tokio::time::sleep(std::time::Duration::from_millis(100)).await;

    let provider = CachingJwksProvider::new(
        &url,
        reqwest::Client::new(),
        std::time::Duration::from_secs(3600),
    );

    let err = provider.decoding_keys().await.unwrap_err();
    assert!(
        err.to_string().contains("no usable RSA key"),
        "empty JWKS should produce 'no usable RSA key' error, got: {err}"
    );
}

#[test]
fn normalize_b64_converts_base64url_to_standard() {
    // Base64url input: no padding, URL-safe chars.
    let url_safe = "SGVsbG8tXyE_";
    let result = normalize_b64(url_safe);
    // Decoding should succeed and produce the original bytes, which when
    // re-encoded as standard base64 gives the expected standard string.
    let decoded = base64::Engine::decode(&base64::engine::general_purpose::STANDARD, &result)
        .expect("normalize_b64 output must be valid standard base64");
    assert_eq!(
        std::str::from_utf8(&decoded).unwrap(),
        "Hello-_!?",
        "normalize_b64 must correctly decode base64url input"
    );

    // Standard base64 input passes through unchanged.
    let standard = "SGVsbG8tXyE/";
    let result2 = normalize_b64(standard);
    assert_eq!(
        result2, standard,
        "standard base64 must pass through unchanged"
    );

    // Invalid base64 input produces an empty string.
    let invalid = "!!!not-base64!!";
    let result3 = normalize_b64(invalid);
    assert!(
        result3.is_empty(),
        "invalid base64 must produce empty string"
    );
}
