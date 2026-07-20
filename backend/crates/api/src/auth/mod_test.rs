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
