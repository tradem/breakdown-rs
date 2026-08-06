// SPDX-License-Identifier: AGPL-3.0
#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::panic,
    clippy::print_stdout,
    clippy::print_stderr,
    clippy::dbg_macro
)]
use api::auth::JwksProvider;
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: mimo-v2.5 (opencode-go)
// Co-authored-by: gpt-5.6-luna (opencode-go)

use api::auth::jwks::{CachingJwksProvider, StaticJwksProvider, normalize_b64};
use jsonwebtoken::{Algorithm, DecodingKey, EncodingKey, Header, Validation, decode, encode};
// `rsa` 0.9 is still built against rand_core 0.6 and its `RsaPrivateKey::new`
// generic bound is rand_core 0.6's `CryptoRngCore`. rand_core 0.10 removed
// `OsRng` from the crate root and its traits are a different version, so we
// must use rsa's own rand_core re-export to get a matching `OsRng`.
use rsa::{RsaPrivateKey, pkcs1::EncodeRsaPrivateKey, rand_core::OsRng, traits::PublicKeyParts};
use std::collections::HashMap;
use std::sync::{
    Arc,
    atomic::{AtomicUsize, Ordering},
};
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

#[tokio::test]
async fn caching_provider_only_accepts_rsa_signing_keys_with_kids() {
    let (jwks, private_key) = test_jwks();
    let (url, request_count, server) = spawn_jwks_server(jwks).await;
    let provider = CachingJwksProvider::new(url, reqwest::Client::new(), Duration::from_secs(3600));

    let keys = provider.decoding_keys().await.unwrap();

    assert_eq!(request_count.load(Ordering::SeqCst), 1);
    assert_eq!(keys.len(), 1);
    let signing_key = keys.get("signing").unwrap();

    // Verify that the accepted key is not merely syntactically decodable: it
    // must also be the public key corresponding to the generated private key.
    let private_key_der = private_key.to_pkcs1_der().unwrap();
    let token = encode(
        &Header::new(Algorithm::RS256),
        &serde_json::json!({ "sub": "test", "exp": 4_000_000_000_u64 }),
        &EncodingKey::from_rsa_der(private_key_der.as_bytes()),
    )
    .unwrap();
    let decoded =
        decode::<serde_json::Value>(&token, signing_key, &Validation::new(Algorithm::RS256))
            .unwrap();
    assert_eq!(decoded.claims["sub"], "test");
    server.abort();
}

#[tokio::test(flavor = "current_thread", start_paused = true)]
async fn caching_provider_refreshes_at_and_after_ttl_boundary() {
    let ttl = Duration::from_secs(60);
    let (jwks, _) = test_jwks();
    let (url, request_count, server) = spawn_jwks_server(jwks).await;
    let provider = CachingJwksProvider::new(url, reqwest::Client::new(), ttl);

    provider.decoding_keys().await.unwrap();
    assert_eq!(request_count.load(Ordering::SeqCst), 1);

    // The comparison is intentionally strict: at exactly the TTL the cache is
    // stale and must be fetched again.
    tokio::time::advance(ttl).await;
    provider.decoding_keys().await.unwrap();
    assert_eq!(request_count.load(Ordering::SeqCst), 2);

    // A cache that is older than the TTL must also be refreshed. This catches
    // the inverse (`>`) mutation independently of the exact-boundary check.
    tokio::time::advance(ttl + Duration::from_nanos(1)).await;
    provider.decoding_keys().await.unwrap();
    assert_eq!(request_count.load(Ordering::SeqCst), 3);
    server.abort();
}

fn test_jwks() -> (serde_json::Value, RsaPrivateKey) {
    let private_key = RsaPrivateKey::new(&mut OsRng, 2048).unwrap();
    let n = base64::Engine::encode(
        &base64::engine::general_purpose::URL_SAFE_NO_PAD,
        private_key.n().to_bytes_be(),
    );
    let e = base64::Engine::encode(
        &base64::engine::general_purpose::URL_SAFE_NO_PAD,
        private_key.e().to_bytes_be(),
    );

    (
        serde_json::json!({
            "keys": [
                { "kty": "RSA", "kid": "signing", "use": "sig", "n": n, "e": e },
                { "kty": "RSA", "kid": "encryption", "use": "enc", "n": n, "e": e },
                { "kty": "EC", "kid": "elliptic", "use": "sig", "n": n, "e": e },
                { "kty": "RSA", "use": "sig", "n": n, "e": e }
            ]
        }),
        private_key,
    )
}

async fn spawn_jwks_server(
    body: serde_json::Value,
) -> (String, Arc<AtomicUsize>, tokio::task::JoinHandle<()>) {
    let request_count = Arc::new(AtomicUsize::new(0));
    let request_count_for_handler = Arc::clone(&request_count);
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let address = listener.local_addr().unwrap();
    let app = axum::Router::new().route(
        "/jwks",
        axum::routing::get(move || {
            request_count_for_handler.fetch_add(1, Ordering::SeqCst);
            let body = body.clone();
            async move { axum::Json(body) }
        }),
    );
    let server = tokio::spawn(async move {
        let _ = axum::serve(listener, app.into_make_service()).await;
    });

    (format!("http://{address}/jwks"), request_count, server)
}
