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

    async fn ensure_key(&self, key_id: &str) -> Result<(), DomainError> {
        let response = self
            .send::<()>(
                reqwest::Method::GET,
                &format!("transit/keys/{key_id}"),
                None,
            )
            .await?;
        if response.status().is_success() {
            return Ok(());
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
            Ok(())
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

#[async_trait::async_trait]
impl CredentialVault for VaultClient {
    async fn store(
        &self,
        settings_id: Uuid,
        provider: &str,
        secret: SecretValue,
    ) -> Result<VaultBinding, DomainError> {
        let key_id = format!("settings-{settings_id}");
        self.ensure_key(&key_id).await?;
        let datakey = self.datakey(&key_id).await?;
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
                &format!("kv/data/settings-secrets/{settings_id}"),
                Some(&KvRequest {
                    data: KvData {
                        provider,
                        vault_key_id: &key_id,
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
            vault_key_id: key_id,
            vault_version: 1,
        })
    }

    async fn fetch(
        &self,
        settings_id: Uuid,
        vault_key_id: &str,
    ) -> Result<SecretValue, DomainError> {
        let response = self
            .send::<()>(
                reqwest::Method::GET,
                &format!("kv/data/settings-secrets/{settings_id}"),
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
        let expected_key_id = format!("settings-{settings_id}");
        if envelope.data.vault_key_id != vault_key_id || vault_key_id != expected_key_id {
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
        let plaintext = String::from_utf8(plaintext)
            .map_err(|_| Self::unavailable("credential is not valid UTF-8"))?;
        Ok(SecretValue::new(plaintext))
    }

    async fn destroy(&self, settings_id: Uuid, vault_key_id: &str) -> Result<(), DomainError> {
        let expected_key_id = format!("settings-{settings_id}");
        if vault_key_id != expected_key_id {
            return Err(Self::unavailable("invalid credential Vault key reference"));
        }
        let config = self
            .send(
                reqwest::Method::POST,
                &format!("transit/keys/{vault_key_id}/config"),
                Some(&serde_json::json!({ "deletion_allowed": true })),
            )
            .await?;
        if !config.status().is_success() {
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
        if !response.status().is_success() {
            return Err(Self::unavailable(format!(
                "key destruction returned {}",
                response.status()
            )));
        }
        let metadata = self
            .send::<()>(
                reqwest::Method::DELETE,
                &format!("kv/metadata/settings-secrets/{settings_id}"),
                None,
            )
            .await?;
        if !metadata.status().is_success() {
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
    use super::{decrypt_envelope, encrypt_envelope};

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
}
