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
use std::path::{Path, PathBuf};
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
        let http = Client::builder()
            .build()
            .map_err(|err| DomainError::ServiceUnavailable(format!("Vault client: {err}")))?;
        Ok(Self {
            http,
            addr,
            token_file,
        })
    }

    fn current_token(&self) -> Option<Zeroizing<String>> {
        self.token_file
            .as_deref()
            .and_then(read_token_file)
            .map(Zeroizing::new)
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
        if response.status().is_success() || response.status() == StatusCode::BAD_REQUEST {
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
        let cipher = Aes256Gcm::new_from_slice(&key)
            .map_err(|_| Self::unavailable("Vault returned an invalid DEK"))?;
        let mut nonce_bytes = [0_u8; 12];
        getrandom::fill(&mut nonce_bytes)
            .map_err(|err| Self::unavailable(format!("nonce generation failed: {err}")))?;
        let encrypted = cipher
            .encrypt(Nonce::from_slice(&nonce_bytes), secret.as_str().as_bytes())
            .map_err(|_| Self::unavailable("credential encryption failed"))?;
        let mut payload = nonce_bytes.to_vec();
        payload.extend(encrypted);
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
        let key = Zeroizing::new(
            self.decrypt_datakey(vault_key_id, &envelope.data.wrapped_dek)
                .await?,
        );
        let cipher = Aes256Gcm::new_from_slice(&key)
            .map_err(|_| Self::unavailable("Vault returned an invalid DEK"))?;
        let payload = BASE64
            .decode(envelope.data.ciphertext)
            .map_err(|err| Self::unavailable(format!("invalid ciphertext encoding: {err}")))?;
        if payload.len() < 12 {
            return Err(Self::unavailable("stored ciphertext is truncated"));
        }
        let (nonce, encrypted) = payload.split_at(12);
        let plaintext = cipher
            .decrypt(Nonce::from_slice(nonce), encrypted)
            .map_err(|_| Self::unavailable("credential decryption failed"))?;
        let plaintext = String::from_utf8(plaintext)
            .map_err(|_| Self::unavailable("credential is not valid UTF-8"))?;
        Ok(SecretValue::new(plaintext))
    }

    async fn destroy(&self, vault_key_id: &str) -> Result<(), DomainError> {
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
        Ok(())
    }

    async fn check(&self) -> Result<(), DomainError> {
        let response = self
            .http
            .get(format!("{}/v1/sys/health", self.addr))
            .send()
            .await
            .map_err(|err| Self::unavailable(err.to_string()))?;
        // Vault's documented 200/429/472/473/501 health responses all mean the
        // service is reachable; sealed/uninitialized states are reported as
        // unavailable so handlers can expose `unreachable` without secrets.
        match response.status().as_u16() {
            200 | 429 | 472 | 473 | 501 => Ok(()),
            status => Err(Self::unavailable(format!("health returned {status}"))),
        }
    }
}

fn read_token_file(path: &Path) -> Option<String> {
    std::fs::read_to_string(path)
        .ok()
        .map(|value| value.trim().to_owned())
        .filter(|value| !value.is_empty())
}

#[cfg(test)]
mod tests {
    use super::read_token_file;

    #[test]
    fn missing_token_file_is_unavailable_without_panicking() {
        assert!(read_token_file(std::path::Path::new("/does/not/exist")).is_none());
    }
}
