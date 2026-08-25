// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4-flash (opencode-go)
// Co-authored-by: gpt-5.6-luna (opencode-go)
// Co-authored-by: mimo-v2.5 (opencode-go)

//! In-transit TLS helpers shared by the S3 adapters (ADR-024 / issue #156).
//!
//! Garage ships **no native TLS** on its S3 API endpoint, so both the photo
//! storage link and the report-archival S3 links are fronted by the Caddy
//! reverse proxy on a Docker-internal TLS port (see `backend/Caddyfile`,
//! internal site). Those endpoints serve a certificate issued by the internal
//! `step-ca`, so the OpenDAL S3 client must **pin the step-ca root** instead
//! of trusting the system store.
//!
//! OpenDAL 0.58 replaced the builder-level `http_client` hook (which accepted
//! an `opendal::raw::HttpClient`) with a per-operator HTTP stack: an
//! [`opendal::HttpTransporter`] attached via [`opendal::OperationContext`].
//! We therefore build a `reqwest::Client` carrying the pinned root (via
//! `add_root_certificate`) and wrap it in a small [`opendal::HttpTransport`]
//! implementation ([`PinnedRootTransport`]) that mirrors the reference
//! `opendal-http-transport-reqwest` adapter. Operators built without a root
//! cert keep the process-wide default transport installed by the `opendal`
//! facade.

use std::mem;

use futures::TryStreamExt;
use futures::future;
use http::{Request, Response};
use opendal::raw::{parse_content_encoding, parse_content_length};
use opendal::services::S3;
use opendal::{
    Buffer, Error, ErrorKind, HttpBody, HttpTransport, HttpTransporter, OperationContext, Operator,
    Result,
};

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

/// An [`opendal::HttpTransport`] backed by a `reqwest::Client` pinned to the
/// internal step-ca root (ADR-024).
///
/// Mirrors the request/response mapping of `opendal-http-transport-reqwest`
/// (the process-wide default transport) so pinned operators behave
/// identically, only with the added root certificate.
#[derive(Clone)]
struct PinnedRootTransport {
    client: reqwest::Client,
}

impl HttpTransport for PinnedRootTransport {
    async fn fetch(&self, req: Request<Buffer>) -> Result<Response<HttpBody>> {
        let uri = req.uri().clone();
        let is_head = req.method() == http::Method::HEAD;

        let (parts, body) = req.into_parts();

        let url = reqwest::Url::parse(&uri.to_string()).map_err(|err| {
            Error::new(ErrorKind::Unexpected, "request url is invalid")
                .with_operation("pinned_reqwest::fetch")
                .with_context("url", uri.to_string())
                .set_source(err)
        })?;

        let mut req_builder = self
            .client
            .request(parts.method, url)
            .headers(parts.headers)
            .version(parts.version);

        if should_send_body(is_head, &body) {
            req_builder = req_builder.body(reqwest::Body::from(body.to_vec()));
        }

        let mut resp = req_builder.send().await.map_err(|err| {
            Error::new(ErrorKind::Unexpected, "send http request")
                .with_operation("pinned_reqwest::send")
                .with_context("url", uri.to_string())
                .with_temporary(is_temporary_error(&err))
                .set_source(err)
        })?;

        let content_length = effective_content_length(is_head, resp.headers())
            .map_err(|e| Error::new(ErrorKind::Unexpected, &e))?;

        let status = resp.status();
        let version = resp.version();
        let headers = mem::take(resp.headers_mut());

        let stream = resp
            .bytes_stream()
            .try_filter(|v| future::ready(!v.is_empty()))
            .map_ok(Buffer::from)
            .map_err({
                let uri = uri.clone();
                move |err| {
                    Error::new(ErrorKind::Unexpected, "read data from http response")
                        .with_operation("pinned_reqwest::fetch")
                        .with_context("url", uri.to_string())
                        .with_temporary(is_temporary_error(&err))
                        .set_source(err)
                }
            });

        let mut http_resp = Response::builder()
            .status(status)
            .version(version)
            .extension(uri)
            .body(HttpBody::new(stream, content_length))
            .map_err(|err| {
                Error::new(ErrorKind::Unexpected, "failed to build http response").set_source(err)
            })?;
        *http_resp.headers_mut() = headers;
        Ok(http_resp)
    }
}

/// Determine the effective content length for an `HttpBody`.
///
/// Returns `None` (unknown/streaming) for HEAD responses or when a
/// content-encoding was applied (the declared length does not match the
/// decoded body). Extracted so the decision logic is unit-testable.
pub fn effective_content_length(
    is_head: bool,
    headers: &http::HeaderMap,
) -> Result<Option<u64>, String> {
    if is_head
        || parse_content_encoding(headers)
            .map_err(|e| e.to_string())?
            .is_some()
    {
        Ok(None)
    } else {
        parse_content_length(headers).map_err(|e| e.to_string())
    }
}

/// Determine whether an outgoing request should carry its body.
///
/// Mirrors the reference `opendal-http-transport-reqwest` adapter: an
/// empty buffer means no body (e.g. GET/HEAD).
pub fn should_send_body(is_head: bool, body: &Buffer) -> bool {
    !is_head && !body.is_empty()
}

/// Classify a reqwest failure as temporary (retryable), mirroring the
/// reference `opendal-http-transport-reqwest` adapter.
pub fn is_temporary_error(err: &reqwest::Error) -> bool {
    err.is_request() || err.is_body() || err.is_decode()
}

/// Build an OpenDAL S3 operator pinned to the given root CA.
///
/// When `root_cert` is `Some(pem_path)` the returned operator pins that CA on
/// the HTTPS endpoint via a custom reqwest transport; otherwise it behaves
/// like the default S3 operator (system trust / plaintext dev endpoints).
///
/// The S3 region is read from `S3_REGION` (default `garage`, matching the
/// Garage `s3_region` config and the integration-test convention); OpenDAL
/// refuses to build an S3 operator without an explicit region.
/// Build the non-SSE S3 operator used by report archival.
pub fn s3_builder(
    endpoint: &str,
    access_key: &str,
    secret_key: &str,
    bucket: &str,
    root_cert: Option<&std::path::Path>,
) -> Result<Operator, String> {
    let builder = s3_builder_base(endpoint, access_key, secret_key, bucket)?;
    build_operator(builder, root_cert)
}

/// Build the photo S3 operator with mandatory AES256 SSE-C.
///
/// The customer key is accepted as bytes so OpenDAL computes the required
/// base64 and MD5 headers without exposing either representation to callers.
pub fn s3_builder_with_customer_key(
    endpoint: &str,
    access_key: &str,
    secret_key: &str,
    bucket: &str,
    root_cert: Option<&std::path::Path>,
    customer_key: &[u8],
) -> Result<Operator, String> {
    if customer_key.len() != 32 {
        return Err("SSE-C customer key must be exactly 32 bytes".into());
    }
    let builder = s3_builder_base(endpoint, access_key, secret_key, bucket)?;
    let builder = builder.server_side_encryption_with_customer_key("AES256", customer_key);
    build_operator(builder, root_cert)
}

fn s3_builder_base(
    endpoint: &str,
    access_key: &str,
    secret_key: &str,
    bucket: &str,
) -> Result<S3, String> {
    let region = std::env::var("S3_REGION").unwrap_or_else(|_| "garage".to_string());
    Ok(S3::default()
        .endpoint(endpoint)
        .region(&region)
        .access_key_id(access_key)
        .secret_access_key(secret_key)
        .bucket(bucket))
}

/// Wrap an S3 service builder in an [`Operator`], attaching the pinned-root
/// reqwest transport when a root certificate is configured.
fn build_operator(builder: S3, root_cert: Option<&std::path::Path>) -> Result<Operator, String> {
    let op = Operator::new(builder).map_err(|e| format!("Failed to create S3 operator: {e}"))?;
    let Some(root) = root_cert else {
        return Ok(op);
    };

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

    let transport = HttpTransporter::new(PinnedRootTransport { client });
    Ok(op.with_context(OperationContext::new().with_http_transport(transport)))
}
