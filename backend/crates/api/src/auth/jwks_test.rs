// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors

use super::*;
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
