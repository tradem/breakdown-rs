// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (neuralwatt)

//! Unit tests for the AI provider `User-Agent` resolution (issue #521).
//!
//! Env-var mutation is process-global, so every test that touches
//! `AI_IMPORT_USER_AGENT*` serializes through [`env_guard`]. No guard is ever
//! held across an `.await` (clippy `await_holding_lock` is deny): the async
//! test resolves the agent inside a scoped helper and drops the lock first.

use std::io::{Read, Write};
use std::net::{SocketAddr, TcpListener};
use std::sync::{Arc, Mutex, MutexGuard};
use std::time::Duration;

use breakdown_core::ai::LlmProvider;

use super::{AI_USER_AGENT_ENV, default_user_agent, provider_override_env, resolve_user_agent};

/// Serializes env-var access across the parallel tests in this module. Only
/// this module reads the `AI_IMPORT_USER_AGENT*` variables, so a local lock is
/// sufficient to keep the tests deterministic.
static ENV_LOCK: Mutex<()> = Mutex::new(());

fn env_guard() -> MutexGuard<'static, ()> {
    ENV_LOCK
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner())
}

#[allow(unsafe_code)]
fn set_var(key: &str, value: Option<&str>) {
    // SAFETY: test-only helper; callers hold `ENV_LOCK` and only this module
    // reads these variables.
    unsafe {
        match value {
            Some(value) => std::env::set_var(key, value),
            None => std::env::remove_var(key),
        }
    }
}

/// Resolve the agent with the given overrides applied, restoring the original
/// env state before returning. The returned `String` is the wire value.
fn resolve_with_overrides(
    provider: LlmProvider,
    global: Option<&str>,
    per_provider: Option<&str>,
) -> String {
    let _guard = env_guard();
    let provider_key = provider_override_env(provider);
    let global_original = std::env::var(AI_USER_AGENT_ENV).ok();
    let provider_original = std::env::var(&provider_key).ok();
    set_var(AI_USER_AGENT_ENV, global);
    set_var(&provider_key, per_provider);
    let resolved = resolve_user_agent(provider);
    set_var(AI_USER_AGENT_ENV, global_original.as_deref());
    set_var(&provider_key, provider_original.as_deref());
    resolved.to_str().unwrap_or_default().to_owned()
}

// ===========================================================================
// Default + env naming
// ===========================================================================

#[test]
fn default_user_agent_is_descriptive_and_stable() {
    let agent = default_user_agent();
    assert!(
        agent.starts_with("breakdown-rs-backend/"),
        "default agent must name the application: {agent}"
    );
    assert!(
        agent.ends_with("(ai-import)"),
        "default agent must name the subsystem: {agent}"
    );
    assert!(
        agent.contains(env!("CARGO_PKG_VERSION")),
        "default agent must carry the crate version: {agent}"
    );
}

#[test]
fn provider_override_env_names_the_provider() {
    assert_eq!(
        provider_override_env(LlmProvider::OpenAI),
        "AI_IMPORT_USER_AGENT_OPENAI"
    );
    assert_eq!(
        provider_override_env(LlmProvider::OpenCodeGo),
        "AI_IMPORT_USER_AGENT_OPENCODE_GO"
    );
    assert_eq!(
        provider_override_env(LlmProvider::OpenCode),
        "AI_IMPORT_USER_AGENT_OPENCODE"
    );
    assert_eq!(
        provider_override_env(LlmProvider::Ollama),
        "AI_IMPORT_USER_AGENT_OLLAMA"
    );
}

// ===========================================================================
// Resolution precedence
// ===========================================================================

#[test]
fn resolves_the_stable_default_without_overrides() {
    let agent = resolve_with_overrides(LlmProvider::OpenCodeGo, None, None);
    assert_eq!(agent, default_user_agent());
}

#[test]
fn global_override_applies_to_every_provider() {
    let agent = resolve_with_overrides(LlmProvider::OpenAI, Some("global/9.9.9"), None);
    assert_eq!(agent, "global/9.9.9");
}

#[test]
fn per_provider_override_wins_over_the_global_one() {
    let agent = resolve_with_overrides(
        LlmProvider::OpenCodeGo,
        Some("global/9.9.9"),
        Some("opencode/1.0.0"),
    );
    assert_eq!(agent, "opencode/1.0.0");
}

#[test]
fn per_provider_override_does_not_leak_to_other_providers() {
    let agent = resolve_with_overrides(LlmProvider::OpenAI, None, None);
    // Set only for OpenCodeGo, then resolve OpenAI — must stay on the default.
    let _guard = env_guard();
    set_var(
        &provider_override_env(LlmProvider::OpenCodeGo),
        Some("opencode/1.0.0"),
    );
    let openai = resolve_user_agent(LlmProvider::OpenAI);
    set_var(&provider_override_env(LlmProvider::OpenCodeGo), None);
    assert_eq!(agent, default_user_agent());
    assert_eq!(openai.to_str().unwrap(), default_user_agent());
}

#[test]
fn override_is_trimmed() {
    let agent = resolve_with_overrides(LlmProvider::OpenAI, Some("  spaced/1  "), None);
    assert_eq!(agent, "spaced/1");
}

#[test]
fn empty_override_falls_through_to_the_default() {
    let agent = resolve_with_overrides(LlmProvider::OpenAI, Some("   "), None);
    assert_eq!(agent, default_user_agent());
}

#[test]
fn header_invalid_override_falls_through_to_the_default() {
    // A newline can never be a header value; a mistyped operator value must
    // not break AI import.
    let agent = resolve_with_overrides(LlmProvider::OpenAI, Some("bad\nvalue"), None);
    assert_eq!(agent, default_user_agent());
}

// ===========================================================================
// End-to-end: the resolved agent is actually sent on the wire
// ===========================================================================

/// Minimal HTTP/1.1 server that records the `User-Agent` header of the first
/// request and answers `200`.
fn spawn_capture_server() -> (SocketAddr, Arc<Mutex<Option<String>>>) {
    let listener = TcpListener::bind("127.0.0.1:0")
        .unwrap_or_else(|error| panic!("cannot bind capture server: {error}"));
    let address = listener
        .local_addr()
        .unwrap_or_else(|error| panic!("cannot read capture server address: {error}"));
    let captured = Arc::new(Mutex::new(None));
    let captured_server = captured.clone();
    std::thread::spawn(move || {
        for stream in listener.incoming() {
            let Ok(mut stream) = stream else { continue };
            let captured = captured_server.clone();
            std::thread::spawn(move || {
                let mut buffer = [0u8; 4096];
                let Ok(read) = stream.read(&mut buffer) else {
                    return;
                };
                let request = String::from_utf8_lossy(&buffer[..read]).to_string();
                let user_agent = request.lines().find_map(|line| {
                    let (name, value) = line.split_once(':')?;
                    name.eq_ignore_ascii_case("user-agent")
                        .then(|| value.trim().to_owned())
                });
                *captured
                    .lock()
                    .unwrap_or_else(|poisoned| poisoned.into_inner()) = user_agent;
                // Test helper: the local capture server discards write errors
                // intentionally — the client-side assertion decides the
                // outcome. ast-grep-ignore: discard-result
                let _ = stream.write_all(
                    b"HTTP/1.1 200 OK\r\nContent-Length: 0\r\nConnection: close\r\n\r\n",
                );
            });
        }
    });
    (address, captured)
}

#[tokio::test]
async fn configured_user_agent_is_sent_on_outgoing_requests() {
    let (address, captured) = spawn_capture_server();
    // Resolve (and restore env) before any await so no std lock is held across
    // it (clippy `await_holding_lock`).
    let configured = resolve_with_overrides(
        LlmProvider::OpenAI,
        Some("breakdown-test/1.2.3 (ai-import)"),
        None,
    );

    let client = reqwest::Client::builder()
        .timeout(Duration::from_secs(5))
        .user_agent(configured.clone())
        .build()
        .unwrap_or_else(|error| panic!("cannot build test client: {error}"));
    let response = client
        .get(format!("http://{address}/probe"))
        .send()
        .await
        .unwrap_or_else(|error| panic!("request failed: {error}"));
    assert_eq!(response.status(), reqwest::StatusCode::OK);

    let seen = captured
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner())
        .clone();
    assert_eq!(
        seen.as_deref(),
        Some(configured.as_str()),
        "the configured User-Agent must reach the provider"
    );
}

#[tokio::test]
async fn default_user_agent_is_sent_on_outgoing_requests() {
    let (address, captured) = spawn_capture_server();
    let configured = resolve_with_overrides(LlmProvider::Ollama, None, None);

    let client = reqwest::Client::builder()
        .timeout(Duration::from_secs(5))
        .user_agent(configured.clone())
        .build()
        .unwrap_or_else(|error| panic!("cannot build test client: {error}"));
    let response = client
        .get(format!("http://{address}/probe"))
        .send()
        .await
        .unwrap_or_else(|error| panic!("request failed: {error}"));
    assert_eq!(response.status(), reqwest::StatusCode::OK);

    let seen = captured
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner())
        .clone();
    assert_eq!(
        seen.as_deref(),
        Some(default_user_agent()),
        "the default User-Agent must reach the provider"
    );
}
