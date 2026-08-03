// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4-flash (opencode-go)

#![allow(clippy::unwrap_used, clippy::expect_used, clippy::panic)]
//! Vault adapter tests (moved from inline `#[cfg(test)]` per Issue #127
//! Variante B): photo SSE-C key provisioning/CAS, credential envelopes, and
//! datakey validation, driven by an in-process HTTP stub.

use std::io::{BufRead, BufReader, Read, Write};
use std::net::TcpListener;
use std::path::PathBuf;
use std::sync::{Arc, Mutex};
use std::thread;

use base64::{Engine as _, engine::general_purpose::STANDARD as BASE64};
use breakdown_core::error::DomainError;
use infra::vault::{
    PHOTO_SSE_C_KEY_ID, VaultClient, decrypt_envelope, encrypt_envelope, validate_binding_key,
};

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
    let client = VaultClient::for_test(format!("http://{address}"), Some(token_path.clone()));
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
    let client = VaultClient::for_test("http://127.0.0.1:1".into(), None);
    let result = client.photo_sse_c_key().await;
    assert!(matches!(result, Err(DomainError::ServiceUnavailable(_))));
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
