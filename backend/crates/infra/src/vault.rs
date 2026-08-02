// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: gpt-5.6-luna (opencode-go)
//! HashiCorp Vault adapter for external credential material (ADR-027).
//!
//! The client is deliberately lazy: an unavailable Vault must not prevent the
//! API from booting. Every operation returns `ServiceUnavailable` until Vault
//! and its least-privilege app token are reachable.

use aes_gcm::{Aes256Gcm, KeyInit, Nonce, aead::Aead};
use base64::{Engine as _, engine::general_purpose::STANDARD as BASE64};
use breakdown_core::error::DomainError;
use breakdown_core::settings::ports::{CredentialVault, SecretValue, VaultBinding};
use reqwest::{Client, StatusCode};
use serde::{Deserialize, Serialize};
use std::fmt;
use std::path::PathBuf;
use std::time::Duration;
use uuid::Uuid;
use zeroize::{Zeroize, Zeroizing};

const PHOTO_SSE_C_KEY_ID: &str = "photo-sse-c";
const PHOTO_SSE_C_KV_PATH: &str = "kv/data/photo-sse-c";

#[derive(Clone)]
pub struct VaultClient {
    http: Client,
    addr: String,
    token_file: Option<PathBuf>,
}

impl fmt::Debug for VaultClient {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("VaultClient")
            .field("addr", &self.addr)
            .field("configured", &self.token_file.is_some())
            .finish()
    }
}

impl VaultClient {
    pub fn from_env() -> Result<Self, DomainError> {
        let addr = std::env::var("VAULT_ADDR")
            .unwrap_or_else(|_| "http://127.0.0.1:8200".to_owned())
            .trim_end_matches('/')
            .to_owned();
        let token_file = std::env::var("VAULT_APP_TOKEN_FILE")
            .ok()
            .filter(|path| !path.trim().is_empty())
            .map(PathBuf::from);
        let mut http_builder = Client::builder()
            .connect_timeout(Duration::from_secs(2))
            .timeout(Duration::from_secs(5));
        if let Some(cert_path) = std::env::var("VAULT_TLS_ROOT_CERT")
            .ok()
            .filter(|path| !path.trim().is_empty())
        {
            let pem = std::fs::read(&cert_path).map_err(|err| {
                DomainError::ServiceUnavailable(format!(
                    "Vault TLS root certificate {cert_path}: {err}"
                ))
            })?;
            let certificate = reqwest::Certificate::from_pem(&pem).map_err(|err| {
                DomainError::ServiceUnavailable(format!(
                    "Vault TLS root certificate {cert_path}: {err}"
                ))
            })?;
            http_builder = http_builder.add_root_certificate(certificate);
        }
        let http = http_builder
            .build()
            .map_err(|err| DomainError::ServiceUnavailable(format!("Vault client: {err}")))?;
        Ok(Self {
            http,
            addr,
            token_file,
        })
    }

    async fn current_token(&self) -> Option<Zeroizing<String>> {
        let path = self.token_file.as_deref()?;
        match tokio::fs::read_to_string(path).await {
            Ok(value) => {
                let value = value.trim().to_owned();
                if value.is_empty() {
                    tracing::warn!(path = %path.display(), "Vault app-token file is empty");
                    None
                } else {
                    Some(Zeroizing::new(value))
                }
            }
            Err(error) => {
                tracing::warn!(path = %path.display(), error = %error, "failed to read Vault app-token file");
                None
            }
        }
    }

    fn unavailable(detail: impl Into<String>) -> DomainError {
        DomainError::ServiceUnavailable(format!("Vault unavailable: {}", detail.into()))
    }

    async fn send<T: Serialize + ?Sized>(
        &self,
        method: reqwest::Method,
        path: &str,
        body: Option<&T>,
    ) -> Result<reqwest::Response, DomainError> {
        let token = self
            .current_token()
            .await
            .ok_or_else(|| Self::unavailable("app token is not configured"))?;
        let url = format!("{}/v1/{}", self.addr, path.trim_start_matches('/'));
        let mut request = self
            .http
            .request(method, url)
            .header("X-Vault-Token", token.as_str());
        if let Some(body) = body {
            request = request.json(body);
        }
        request
            .send()
            .await
            .map_err(|err| Self::unavailable(err.to_string()))
    }

    async fn ensure_key(&self, key_id: &str) -> Result<bool, DomainError> {
        let response = self
            .send::<()>(
                reqwest::Method::GET,
                &format!("transit/keys/{key_id}"),
                None,
            )
            .await?;
        if response.status().is_success() {
            return Ok(false);
        }
        if response.status() != StatusCode::NOT_FOUND {
            return Err(Self::unavailable(format!(
                "key lookup returned {}",
                response.status()
            )));
        }
        let response = self
            .send(
                reqwest::Method::POST,
                &format!("transit/keys/{key_id}"),
                Some(&CreateKeyRequest {
                    key_type: "aes256-gcm96",
                    exportable: false,
                }),
            )
            .await?;
        if response.status().is_success() {
            Ok(true)
        } else {
            Err(Self::unavailable(format!(
                "key creation returned {}",
                response.status()
            )))
        }
    }

    async fn datakey(&self, key_id: &str) -> Result<DataKeyResponse, DomainError> {
        let response = self
            .send::<()>(
                reqwest::Method::POST,
                &format!("transit/datakey/plaintext/{key_id}"),
                None,
            )
            .await?;
        if !response.status().is_success() {
            return Err(Self::unavailable(format!(
                "datakey returned {}",
                response.status()
            )));
        }
        response
            .json::<DataKeyEnvelope>()
            .await
            .map(|envelope| envelope.data)
            .map_err(|err| Self::unavailable(format!("invalid datakey response: {err}")))
    }

    async fn decrypt_datakey(&self, key_id: &str, wrapped: &str) -> Result<Vec<u8>, DomainError> {
        let response = self
            .send(
                reqwest::Method::POST,
                &format!("transit/decrypt/{key_id}"),
                Some(&DecryptRequest {
                    ciphertext: wrapped,
                }),
            )
            .await?;
        if !response.status().is_success() {
            return Err(Self::unavailable(format!(
                "datakey decrypt returned {}",
                response.status()
            )));
        }
        let envelope = response
            .json::<PlaintextEnvelope>()
            .await
            .map_err(|err| Self::unavailable(format!("invalid decrypt response: {err}")))?;
        BASE64
            .decode(envelope.data.plaintext)
            .map_err(|err| Self::unavailable(format!("invalid datakey encoding: {err}")))
    }

    /// Load or provision the stable bucket-level SSE-C key for photo storage.
    ///
    /// Only the Transit-wrapped DEK is persisted in Vault KV. The plaintext is
    /// returned in a zeroizing buffer so the API can configure OpenDAL without
    /// putting key material in configuration, events, or logs.
    pub async fn photo_sse_c_key(&self) -> Result<Zeroizing<Vec<u8>>, DomainError> {
        if let Some(wrapped) = self.photo_sse_c_wrapped_key().await? {
            return Self::validated_photo_key(
                self.decrypt_datakey(PHOTO_SSE_C_KEY_ID, &wrapped).await?,
            );
        }

        self.ensure_key(PHOTO_SSE_C_KEY_ID).await?;
        let datakey = self.datakey(PHOTO_SSE_C_KEY_ID).await?;
        let candidate = Self::validated_photo_key(Self::decode_datakey(datakey.plaintext)?)?;
        let response = self
            .send(
                reqwest::Method::POST,
                PHOTO_SSE_C_KV_PATH,
                Some(&PhotoKeyKvRequest {
                    data: PhotoKeyKvData {
                        vault_key_id: PHOTO_SSE_C_KEY_ID,
                        wrapped_dek: &datakey.ciphertext,
                    },
                    options: PhotoKeyKvOptions { cas: 0 },
                }),
            )
            .await?;

        if response.status().is_success() {
            return Ok(candidate);
        }

        // Vault KV-v2 reports a compare-and-set race as a client error. The
        // winner's record is authoritative; never use our losing candidate.
        if (response.status() == StatusCode::BAD_REQUEST
            || response.status() == StatusCode::CONFLICT)
            && let Some(wrapped) = self.photo_sse_c_wrapped_key().await?
        {
            return Self::validated_photo_key(
                self.decrypt_datakey(PHOTO_SSE_C_KEY_ID, &wrapped).await?,
            );
        }

        Err(Self::unavailable(format!(
            "photo SSE-C key write returned {}",
            response.status()
        )))
    }

    async fn photo_sse_c_wrapped_key(&self) -> Result<Option<String>, DomainError> {
        let response = self
            .send::<()>(reqwest::Method::GET, PHOTO_SSE_C_KV_PATH, None)
            .await?;
        if response.status() == StatusCode::NOT_FOUND {
            return Ok(None);
        }
        if !response.status().is_success() {
            return Err(Self::unavailable(format!(
                "photo SSE-C key lookup returned {}",
                response.status()
            )));
        }
        let envelope = response
            .json::<PhotoKeyKvEnvelope>()
            .await
            .map_err(|err| Self::unavailable(format!("invalid photo key response: {err}")))?;
        if envelope.data.data.vault_key_id != PHOTO_SSE_C_KEY_ID
            || envelope.data.data.wrapped_dek.trim().is_empty()
        {
            return Err(Self::unavailable("invalid photo SSE-C key binding"));
        }
        Ok(Some(envelope.data.data.wrapped_dek))
    }

    fn decode_datakey(encoded: String) -> Result<Vec<u8>, DomainError> {
        let mut encoded = encoded;
        let decoded = BASE64
            .decode(&encoded)
            .map_err(|err| Self::unavailable(format!("invalid datakey encoding: {err}")))?;
        encoded.zeroize();
        Ok(decoded)
    }

    fn validated_photo_key(key: Vec<u8>) -> Result<Zeroizing<Vec<u8>>, DomainError> {
        let key = Zeroizing::new(key);
        if key.len() != 32 {
            return Err(Self::unavailable("photo SSE-C datakey must be 32 bytes"));
        }
        Ok(key)
    }
}

#[derive(Serialize)]
struct CreateKeyRequest {
    #[serde(rename = "type")]
    key_type: &'static str,
    exportable: bool,
}

#[derive(Serialize)]
struct DecryptRequest<'a> {
    ciphertext: &'a str,
}

#[derive(Deserialize)]
struct DataKeyEnvelope {
    data: DataKeyResponse,
}

#[derive(Deserialize)]
struct DataKeyResponse {
    ciphertext: String,
    plaintext: String,
}

#[derive(Deserialize)]
struct PlaintextEnvelope {
    data: PlaintextData,
}

#[derive(Deserialize)]
struct PlaintextData {
    plaintext: String,
}

#[derive(Serialize)]
struct KvRequest<'a> {
    data: KvData<'a>,
}

#[derive(Serialize)]
struct KvData<'a> {
    provider: &'a str,
    vault_key_id: &'a str,
    wrapped_dek: &'a str,
    ciphertext: &'a str,
}

#[derive(Deserialize)]
struct KvEnvelope {
    data: KvDataOwned,
}

#[derive(Deserialize)]
struct KvDataOwned {
    vault_key_id: String,
    wrapped_dek: String,
    ciphertext: String,
}

#[derive(Serialize)]
struct PhotoKeyKvRequest<'a> {
    data: PhotoKeyKvData<'a>,
    options: PhotoKeyKvOptions,
}

#[derive(Serialize)]
struct PhotoKeyKvData<'a> {
    vault_key_id: &'static str,
    wrapped_dek: &'a str,
}

#[derive(Serialize)]
struct PhotoKeyKvOptions {
    cas: u8,
}

#[derive(Deserialize)]
struct PhotoKeyKvEnvelope {
    data: PhotoKeyKvResponseData,
}

#[derive(Deserialize)]
struct PhotoKeyKvResponseData {
    data: PhotoKeyKvDataOwned,
}

#[derive(Deserialize)]
struct PhotoKeyKvDataOwned {
    vault_key_id: String,
    wrapped_dek: String,
}

impl VaultClient {
    async fn store_secret(
        &self,
        settings_id: Uuid,
        key_id: &str,
        provider: &str,
        secret: SecretValue,
    ) -> Result<VaultBinding, DomainError> {
        validate_binding_key(settings_id, key_id)?;
        let key_created = self.ensure_key(key_id).await?;
        let result = self
            .store_secret_inner(settings_id, key_id, provider, secret)
            .await;
        if key_created
            && result.is_err()
            && let Err(cleanup_error) = self.destroy(settings_id, key_id).await
        {
            tracing::error!(
                vault_key_id = %key_id,
                error = %cleanup_error,
                "failed to clean up unreferenced Vault binding"
            );
        }
        result
    }

    async fn store_secret_inner(
        &self,
        settings_id: Uuid,
        key_id: &str,
        provider: &str,
        secret: SecretValue,
    ) -> Result<VaultBinding, DomainError> {
        let record_id = record_id_for(settings_id, key_id);
        let datakey = self.datakey(key_id).await?;
        let mut encoded_key = datakey.plaintext;
        let key = Zeroizing::new(
            BASE64
                .decode(&encoded_key)
                .map_err(|err| Self::unavailable(format!("invalid datakey encoding: {err}")))?,
        );
        encoded_key.zeroize();
        let payload =
            encrypt_envelope(&key, secret.as_str().as_bytes()).map_err(Self::unavailable)?;
        let ciphertext = BASE64.encode(payload);
        let response = self
            .send(
                reqwest::Method::POST,
                &format!("kv/data/settings-secrets/{record_id}"),
                Some(&KvRequest {
                    data: KvData {
                        provider,
                        vault_key_id: key_id,
                        wrapped_dek: &datakey.ciphertext,
                        ciphertext: &ciphertext,
                    },
                }),
            )
            .await?;
        if !response.status().is_success() {
            return Err(Self::unavailable(format!(
                "KV write returned {}",
                response.status()
            )));
        }
        Ok(VaultBinding {
            vault_key_id: key_id.to_owned(),
            vault_version: 1,
        })
    }
}

#[async_trait::async_trait]
impl CredentialVault for VaultClient {
    async fn store(
        &self,
        settings_id: Uuid,
        provider: &str,
        secret: SecretValue,
    ) -> Result<VaultBinding, DomainError> {
        let key_id = format!("settings-{settings_id}");
        self.store_secret(settings_id, &key_id, provider, secret)
            .await
    }

    async fn store_gdrive(
        &self,
        settings_id: Uuid,
        bundle: breakdown_core::settings::ports::GDriveCredentialBundle,
    ) -> Result<VaultBinding, DomainError> {
        // A new opaque key per rotation preserves the old binding until the
        // reference-only rotation event has been accepted.
        let key_id = format!("settings-{settings_id}-{}", Uuid::now_v7());
        let secret = bundle.into_secret_value()?;
        self.store_secret(settings_id, &key_id, "gdrive", secret)
            .await
    }

    async fn fetch(
        &self,
        settings_id: Uuid,
        vault_key_id: &str,
    ) -> Result<SecretValue, DomainError> {
        validate_binding_key(settings_id, vault_key_id)?;
        let record_id = record_id_for(settings_id, vault_key_id);
        let response = self
            .send::<()>(
                reqwest::Method::GET,
                &format!("kv/data/settings-secrets/{record_id}"),
                None,
            )
            .await?;
        if !response.status().is_success() {
            return Err(Self::unavailable(format!(
                "KV read returned {}",
                response.status()
            )));
        }
        let envelope = response
            .json::<KvEnvelope>()
            .await
            .map_err(|err| Self::unavailable(format!("invalid KV response: {err}")))?;
        if envelope.data.vault_key_id != vault_key_id {
            return Err(Self::unavailable(
                "credential binding does not match the Vault record",
            ));
        }
        let key = Zeroizing::new(
            self.decrypt_datakey(vault_key_id, &envelope.data.wrapped_dek)
                .await?,
        );
        let payload = BASE64
            .decode(envelope.data.ciphertext)
            .map_err(|err| Self::unavailable(format!("invalid ciphertext encoding: {err}")))?;
        let plaintext = decrypt_envelope(&key, &payload).map_err(Self::unavailable)?;
        let plaintext = String::from_utf8(plaintext).map_err(|error| {
            let mut bytes = error.into_bytes();
            bytes.zeroize();
            Self::unavailable("credential is not valid UTF-8")
        })?;
        Ok(SecretValue::new(plaintext))
    }

    async fn destroy(&self, settings_id: Uuid, vault_key_id: &str) -> Result<(), DomainError> {
        validate_binding_key(settings_id, vault_key_id)?;
        let record_id = record_id_for(settings_id, vault_key_id);
        let config = self
            .send(
                reqwest::Method::POST,
                &format!("transit/keys/{vault_key_id}/config"),
                Some(&serde_json::json!({ "deletion_allowed": true })),
            )
            .await?;
        if !config.status().is_success() && config.status() != StatusCode::NOT_FOUND {
            return Err(Self::unavailable(format!(
                "key configuration returned {}",
                config.status()
            )));
        }
        let response = self
            .send::<()>(
                reqwest::Method::DELETE,
                &format!("transit/keys/{vault_key_id}"),
                None,
            )
            .await?;
        if !response.status().is_success() && response.status() != StatusCode::NOT_FOUND {
            return Err(Self::unavailable(format!(
                "key destruction returned {}",
                response.status()
            )));
        }
        let metadata = self
            .send::<()>(
                reqwest::Method::DELETE,
                &format!("kv/metadata/settings-secrets/{record_id}"),
                None,
            )
            .await?;
        if !metadata.status().is_success() && metadata.status() != StatusCode::NOT_FOUND {
            return Err(Self::unavailable(format!(
                "KV metadata deletion returned {}",
                metadata.status()
            )));
        }
        Ok(())
    }

    async fn check(&self) -> Result<(), DomainError> {
        let response = self
            .http
            .get(format!("{}/v1/sys/health", self.addr))
            .send()
            .await
            .map_err(|err| Self::unavailable(err.to_string()))?;
        // Vault's documented active/standby responses mean the service is
        // reachable; sealed and uninitialized states are unavailable.
        match response.status().as_u16() {
            200 | 429 | 472 | 473 => Ok(()),
            status => Err(Self::unavailable(format!("health returned {status}"))),
        }
    }
}

/// Resolve the KV record id for a validated binding key. Legacy bindings use
/// the bare Settings UUID; rotation bindings use their opaque key id.
fn record_id_for(settings_id: Uuid, vault_key_id: &str) -> String {
    if vault_key_id == format!("settings-{settings_id}") {
        settings_id.to_string()
    } else {
        vault_key_id.to_owned()
    }
}

fn validate_binding_key(settings_id: Uuid, key_id: &str) -> Result<(), DomainError> {
    let prefix = format!("settings-{settings_id}");
    let valid = if key_id == prefix {
        true
    } else if let Some(suffix) = key_id.strip_prefix(&format!("{prefix}-")) {
        Uuid::parse_str(suffix).is_ok()
    } else {
        false
    };
    if valid {
        Ok(())
    } else {
        Err(VaultClient::unavailable(
            "invalid credential Vault key reference",
        ))
    }
}

fn encrypt_envelope(dek: &[u8], plaintext: &[u8]) -> Result<Vec<u8>, &'static str> {
    let cipher = Aes256Gcm::new_from_slice(dek).map_err(|_| "invalid DEK")?;
    let mut nonce_bytes = [0_u8; 12];
    getrandom::fill(&mut nonce_bytes).map_err(|_| "nonce generation failed")?;
    let encrypted = cipher
        .encrypt(Nonce::from_slice(&nonce_bytes), plaintext)
        .map_err(|_| "credential encryption failed")?;
    let mut payload = nonce_bytes.to_vec();
    payload.extend(encrypted);
    Ok(payload)
}

fn decrypt_envelope(dek: &[u8], payload: &[u8]) -> Result<Vec<u8>, &'static str> {
    if payload.len() < 12 {
        return Err("stored ciphertext is truncated");
    }
    let cipher = Aes256Gcm::new_from_slice(dek).map_err(|_| "invalid DEK")?;
    let (nonce, encrypted) = payload.split_at(12);
    cipher
        .decrypt(Nonce::from_slice(nonce), encrypted)
        .map_err(|_| "credential decryption failed")
}

#[cfg(test)]
mod tests {
    use super::{
        PHOTO_SSE_C_KEY_ID, VaultClient, decrypt_envelope, encrypt_envelope, validate_binding_key,
    };
    use base64::{Engine as _, engine::general_purpose::STANDARD as BASE64};
    use std::io::{BufRead, BufReader, Read, Write};
    use std::net::TcpListener;
    use std::path::PathBuf;
    use std::sync::{Arc, Mutex};
    use std::thread;

    fn response(status: &str, body: &str) -> String {
        format!(
            "HTTP/1.1 {status}\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body}",
            body.len()
        )
    }

    fn stub_client(
        conflict: bool,
    ) -> (
        VaultClient,
        thread::JoinHandle<()>,
        PathBuf,
        Arc<Mutex<Vec<String>>>,
    ) {
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let address = listener.local_addr().unwrap();
        let token_path = std::env::temp_dir().join(format!("vault-test-{}", uuid::Uuid::now_v7()));
        std::fs::write(&token_path, "test-token").unwrap();
        let request_bodies = Arc::new(Mutex::new(Vec::new()));
        let captured_bodies = request_bodies.clone();
        let handle = thread::spawn(move || {
            let mut kv_reads = 0_u8;
            for incoming in listener.incoming().take(if conflict { 7 } else { 5 }) {
                let mut stream = incoming.unwrap();
                let mut reader = BufReader::new(stream.try_clone().unwrap());
                let mut request_line = String::new();
                reader.read_line(&mut request_line).unwrap();
                let mut header = String::new();
                let mut content_length = 0_usize;
                while reader.read_line(&mut header).unwrap_or(0) > 0 && header != "\r\n" {
                    if let Some((name, value)) = header.split_once(':')
                        && name.eq_ignore_ascii_case("content-length")
                    {
                        content_length = value.trim().parse().unwrap_or(0);
                    }
                    header.clear();
                }
                let mut request_body = vec![0_u8; content_length];
                reader.read_exact(&mut request_body).unwrap();
                let mut parts = request_line.split_whitespace();
                let method = parts.next().unwrap_or_default();
                let path = parts.next().unwrap_or_default();
                if method == "POST" && path == "/v1/kv/data/photo-sse-c" {
                    captured_bodies
                        .lock()
                        .unwrap()
                        .push(String::from_utf8(request_body).unwrap());
                }
                let (status, body): (&str, String) = match (method, path) {
                    ("GET", "/v1/kv/data/photo-sse-c") if kv_reads == 0 => {
                        kv_reads += 1;
                        ("404 Not Found", "{}".into())
                    }
                    ("GET", "/v1/kv/data/photo-sse-c") => (
                        "200 OK",
                        r#"{"data":{"data":{"vault_key_id":"photo-sse-c","wrapped_dek":"winner-wrapped"}}}"#
                            .into(),
                    ),
                    ("GET", "/v1/transit/keys/photo-sse-c") => ("404 Not Found", "{}".into()),
                    ("POST", "/v1/transit/keys/photo-sse-c") => ("204 No Content", "".into()),
                    ("POST", "/v1/transit/datakey/plaintext/photo-sse-c") => (
                        "200 OK",
                        format!(
                            r#"{{"data":{{"ciphertext":"candidate-wrapped","plaintext":"{}"}}}}"#,
                            BASE64.encode([7_u8; 32])
                        ),
                    ),
                    ("POST", "/v1/kv/data/photo-sse-c") if conflict => {
                        ("400 Bad Request", "{}".into())
                    }
                    ("POST", "/v1/kv/data/photo-sse-c") => ("200 OK", "{}".into()),
                    ("POST", "/v1/transit/decrypt/photo-sse-c") => (
                        "200 OK",
                        format!(
                            r#"{{"data":{{"plaintext":"{}"}}}}"#,
                            BASE64.encode([9_u8; 32])
                        ),
                    ),
                    _ => ("500 Internal Server Error", "{}".into()),
                };
                stream
                    .write_all(response(status, &body).as_bytes())
                    .unwrap();
            }
        });
        let client = VaultClient {
            http: reqwest::Client::new(),
            addr: format!("http://{}", address),
            token_file: Some(token_path.clone()),
        };
        (client, handle, token_path, request_bodies)
    }

    #[tokio::test]
    async fn photo_key_is_provisioned_and_plaintext_is_not_persisted() {
        let (client, handle, token_path, request_bodies) = stub_client(false);
        let key = client.photo_sse_c_key().await.unwrap();
        assert_eq!(key.as_slice(), &[7_u8; 32]);
        handle.join().unwrap();
        let body = request_bodies.lock().unwrap().first().cloned().unwrap();
        assert!(body.contains("wrapped_dek"));
        assert!(!body.contains(&BASE64.encode([7_u8; 32])));
        std::fs::remove_file(token_path).unwrap();
    }

    #[tokio::test]
    async fn photo_key_uses_winner_after_kv_cas_conflict() {
        let (client, handle, token_path, _request_bodies) = stub_client(true);
        let key = client.photo_sse_c_key().await.unwrap();
        assert_eq!(key.as_slice(), &[9_u8; 32]);
        handle.join().unwrap();
        std::fs::remove_file(token_path).unwrap();
    }

    #[tokio::test]
    async fn photo_key_without_vault_token_is_unavailable() {
        let client = VaultClient {
            http: reqwest::Client::new(),
            addr: "http://127.0.0.1:1".into(),
            token_file: None,
        };
        let result = client.photo_sse_c_key().await;
        assert!(matches!(
            result,
            Err(breakdown_core::error::DomainError::ServiceUnavailable(_))
        ));
    }

    #[test]
    fn envelope_round_trip_preserves_plaintext() {
        let dek = [7_u8; 32];
        let payload = encrypt_envelope(&dek, b"refresh-token").unwrap();
        assert_eq!(decrypt_envelope(&dek, &payload).unwrap(), b"refresh-token");
    }

    #[test]
    fn envelope_rejects_truncated_payload() {
        assert!(decrypt_envelope(&[7_u8; 32], &[0_u8; 11]).is_err());
    }

    #[test]
    fn envelope_rejects_modified_ciphertext() {
        let dek = [7_u8; 32];
        let mut payload = encrypt_envelope(&dek, b"secret").unwrap();
        let last = payload.len() - 1;
        payload[last] ^= 1;
        assert!(decrypt_envelope(&dek, &payload).is_err());
    }

    #[test]
    fn binding_key_from_another_settings_id_is_rejected() {
        let settings_id = uuid::Uuid::now_v7();
        let other_id = uuid::Uuid::now_v7();
        let key_id = format!("settings-{other_id}");
        let error = validate_binding_key(settings_id, &key_id).unwrap_err();
        assert!(
            error
                .to_string()
                .contains("invalid credential Vault key reference")
        );
    }

    #[test]
    fn photo_datakey_requires_exactly_32_bytes() {
        let valid = BASE64.encode([7_u8; 32]);
        let decoded = VaultClient::decode_datakey(valid).unwrap();
        assert!(VaultClient::validated_photo_key(decoded).is_ok());

        let invalid = BASE64.encode([7_u8; 31]);
        let decoded = VaultClient::decode_datakey(invalid).unwrap();
        assert!(VaultClient::validated_photo_key(decoded).is_err());
        assert_eq!(PHOTO_SSE_C_KEY_ID, "photo-sse-c");
    }
}
