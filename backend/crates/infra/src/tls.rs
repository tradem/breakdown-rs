// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4-flash (opencode-go)
// Co-authored-by: gpt-5.6-luna (opencode-go)

//! In-transit TLS helpers shared by the S3 adapters (ADR-024 / issue #156).
//!
//! Garage ships **no native TLS** on its S3 API endpoint, so both the photo
//! storage link and the report-archival S3 links are fronted by the Caddy
//! reverse proxy on a Docker-internal TLS port (see `backend/Caddyfile`,
//! internal site). Those endpoints serve a certificate issued by the internal
//! `step-ca`, so the OpenDAL S3 client must **pin the step-ca root** instead
//! of trusting the system store.
//!
//! OpenDAL only exposes the HTTP stack through `opendal::raw::HttpClient`, so
//! we build a `reqwest::Client` carrying the pinned root (via
//! `add_root_certificate`) and hand it to the S3 builder with `http_client`.

use opendal::raw::HttpClient;
use opendal::services::S3;

/// Read the PEM-encoded root CA file referenced by an env var, if set.
///
/// Returns `Ok(None)` when the variable is unset/empty (dev or public-CA
/// endpoints), and `Ok(Some(path))` when set. Errors surface a missing file
/// early so misconfiguration fails fast at startup.
pub fn root_cert_from_env(var: &str) -> Result<Option<std::path::PathBuf>, String> {
    match std::env::var(var) {
        Ok(v) if !v.trim().is_empty() => from_value(v.trim()),
        _ => Ok(None),
    }
}

/// Parse a root-CA path value into a checked `PathBuf`.
///
/// Split out from [`root_cert_from_env`] so the validation logic is testable
/// without mutating process environment (unsafe in edition 2024).
pub fn from_value(value: &str) -> Result<Option<std::path::PathBuf>, String> {
    let value = value.trim();
    if value.is_empty() {
        return Ok(None);
    }
    let path = std::path::PathBuf::from(value);
    if !path.is_file() {
        return Err(format!(
            "TLS root certificate file not found: {}",
            path.display()
        ));
    }
    Ok(Some(path))
}

/// Build an OpenDAL S3 service builder pinned to the given root CA.
///
/// When `root_cert` is `Some(pem_path)` the returned builder pins that CA on
/// the HTTPS endpoint via a custom reqwest client; otherwise it behaves like
/// the default S3 builder (system trust / plaintext dev endpoints).
///
/// The S3 region is read from `S3_REGION` (default `garage`, matching the
/// Garage `s3_region` config and the integration-test convention); OpenDAL
/// refuses to build an S3 operator without an explicit region.
pub fn s3_builder(
    endpoint: &str,
    access_key: &str,
    secret_key: &str,
    bucket: &str,
    root_cert: Option<&std::path::Path>,
) -> Result<S3, String> {
    s3_builder_with_customer_key(endpoint, access_key, secret_key, bucket, root_cert, None)
}

/// Build an OpenDAL S3 service builder with an optional customer-provided key.
///
/// The customer key is intentionally accepted as bytes so OpenDAL can compute
/// the required base64 and MD5 headers without exposing either representation
/// to callers. Report archival uses [`s3_builder`] without a key; photo
/// storage is the only caller that enables SSE-C.
pub fn s3_builder_with_customer_key(
    endpoint: &str,
    access_key: &str,
    secret_key: &str,
    bucket: &str,
    root_cert: Option<&std::path::Path>,
    customer_key: Option<&[u8]>,
) -> Result<S3, String> {
    let region = std::env::var("S3_REGION").unwrap_or_else(|_| "garage".to_string());
    let mut builder = S3::default()
        .endpoint(endpoint)
        .region(&region)
        .access_key_id(access_key)
        .secret_access_key(secret_key)
        .bucket(bucket);

    if let Some(key) = customer_key {
        if key.len() != 32 {
            return Err("SSE-C customer key must be exactly 32 bytes".into());
        }
        builder = builder.server_side_encryption_with_customer_key("AES256", key);
    }

    if let Some(root) = root_cert {
        let pem = std::fs::read(root).map_err(|e| {
            format!(
                "failed to read TLS root certificate {}: {e}",
                root.display()
            )
        })?;
        let cert = reqwest::Certificate::from_pem(&pem).map_err(|e| {
            format!(
                "failed to parse TLS root certificate {}: {e}",
                root.display()
            )
        })?;
        let client = reqwest::Client::builder()
            .add_root_certificate(cert)
            .build()
            .map_err(|e| format!("failed to build pinned-root HTTP client: {e}"))?;
        builder = builder.http_client(HttpClient::with(client));
    }

    Ok(builder)
}
