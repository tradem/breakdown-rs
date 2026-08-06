// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: gpt-5.6-luna (opencode-go)
// Co-authored-by: deepseek-v4-flash (opencode-go)
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

/// Fixed non-secret identifier of the bucket-level photo SSE-C key.
pub const PHOTO_SSE_C_KEY_ID: &str = "photo-sse-c";
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
    /// Build a client against an explicit address + token file without reading
    /// environment variables.
    ///
    /// `#[doc(hidden)]`: only used by the external tests in `tests/` (Issue
    /// #127 test layout) to point a client at an in-process HTTP stub. Gated
    /// behind `test-support` so production builds never expose the
    /// arbitrary-address constructor.
    #[doc(hidden)]
    #[cfg(feature = "test-support")]
    pub fn for_test(addr: String, token_file: Option<PathBuf>) -> Self {
        Self {
            http: Client::new(),
            addr: addr.trim_end_matches('/').to_owned(),
            token_file,
        }
    }

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

    /// Decode the base64 plaintext of a Vault Transit datakey response.
    ///
    /// Zeroizes the input buffer after decoding. `pub` so the external tests
    /// in `tests/` can verify key validation (Issue #127 test layout).
    pub fn decode_datakey(encoded: String) -> Result<Vec<u8>, DomainError> {
        let mut encoded = encoded;
        let decoded = BASE64
            .decode(&encoded)
            .map_err(|err| Self::unavailable(format!("invalid datakey encoding: {err}")))?;
        encoded.zeroize();
        Ok(decoded)
    }

    /// Validate that a photo SSE-C datakey is exactly 32 bytes.
    ///
    /// `pub` so the external tests in `tests/` can verify key validation
    /// (Issue #127 test layout).
    pub fn validated_photo_key(key: Vec<u8>) -> Result<Zeroizing<Vec<u8>>, DomainError> {
        let key = Zeroizing::new(key);
        if key.len() != 32 {
            return Err(Self::unavailable("photo SSE-C datakey must be 32 bytes"));
        }
        Ok(key)
    }
}

// Recoverable photo key source (issue #165): `OpenDalPhotoStorage` calls
// `resolve` lazily on demand and retries after a failure, so a Vault outage
// at boot does not permanently disable photo storage.
#[async_trait::async_trait]
impl crate::photo::storage::PhotoStorageKeySource for VaultClient {
    async fn resolve(&self) -> Result<Zeroizing<Vec<u8>>, DomainError> {
        self.photo_sse_c_key().await
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
    data: KvDataEnvelope,
}

#[derive(Deserialize)]
struct KvDataEnvelope {
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
        if envelope.data.data.vault_key_id != vault_key_id {
            return Err(Self::unavailable(
                "credential binding does not match the Vault record",
            ));
        }
        let key = Zeroizing::new(
            self.decrypt_datakey(vault_key_id, &envelope.data.data.wrapped_dek)
                .await?,
        );
        let payload = BASE64
            .decode(envelope.data.data.ciphertext)
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

/// Validate that a settings secret references the settings-scoped key id.
pub fn validate_binding_key(settings_id: Uuid, key_id: &str) -> Result<(), DomainError> {
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

/// Encrypt a plaintext into a nonce-prefixed AES-256-GCM envelope.
///
/// Used by the settings `CredentialVault` adapter to store secrets at rest in
/// Vault KV. `pub` so the external tests in `tests/` can verify the round trip
/// (Issue #127 test layout).
pub fn encrypt_envelope(dek: &[u8], plaintext: &[u8]) -> Result<Vec<u8>, &'static str> {
    let cipher = Aes256Gcm::new_from_slice(dek).map_err(|_| "invalid DEK")?;
    let mut nonce_bytes = [0_u8; 12];
    getrandom::fill(&mut nonce_bytes).map_err(|_| "nonce generation failed")?;
    let nonce = Nonce::try_from(&nonce_bytes[..]).map_err(|_| "invalid nonce")?;
    let encrypted = cipher
        .encrypt(&nonce, plaintext)
        .map_err(|_| "credential encryption failed")?;
    let mut payload = nonce_bytes.to_vec();
    payload.extend(encrypted);
    Ok(payload)
}

/// Decrypt a nonce-prefixed AES-256-GCM envelope produced by
/// [`encrypt_envelope`].
///
/// `pub` so the external tests in `tests/` can verify the round trip
/// (Issue #127 test layout).
pub fn decrypt_envelope(dek: &[u8], payload: &[u8]) -> Result<Vec<u8>, &'static str> {
    if payload.len() < 12 {
        return Err("stored ciphertext is truncated");
    }
    let cipher = Aes256Gcm::new_from_slice(dek).map_err(|_| "invalid DEK")?;
    let (nonce_bytes, encrypted) = payload.split_at(12);
    let nonce = Nonce::try_from(nonce_bytes).map_err(|_| "invalid nonce")?;
    cipher
        .decrypt(&nonce, encrypted)
        .map_err(|_| "credential decryption failed")
}
