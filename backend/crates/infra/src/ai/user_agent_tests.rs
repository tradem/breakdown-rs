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

/// Run `f` with arbitrary env assignments applied, restoring every touched
/// variable to its original value afterwards. The `ENV_LOCK` guard is held for
/// the duration, so `f` must not `await` (clippy `await_holding_lock`).
fn with_env_vars<R>(vars: &[(&str, Option<&str>)], f: impl FnOnce() -> R) -> R {
    let _guard = env_guard();
    let originals: Vec<(String, Option<String>)> = vars
        .iter()
        .map(|(key, _)| ((*key).to_owned(), std::env::var(key).ok()))
        .collect();
    for (key, value) in vars {
        set_var(key, *value);
    }
    let result = f();
    for (key, original) in &originals {
        set_var(key, original.as_deref());
    }
    result
}

/// Run `f` with the given provider overrides applied, restoring the original
/// env state before returning. `f` must not `await` (the lock is held).
fn with_overrides<R>(
    provider: LlmProvider,
    global: Option<&str>,
    per_provider: Option<&str>,
    f: impl FnOnce() -> R,
) -> R {
    let provider_key = provider_override_env(provider);
    with_env_vars(
        &[
            (AI_USER_AGENT_ENV, global),
            (provider_key.as_str(), per_provider),
        ],
        f,
    )
}

/// Resolve the agent with the given overrides applied, restoring the original
/// env state before returning. The returned `String` is the wire value.
fn resolve_with_overrides(
    provider: LlmProvider,
    global: Option<&str>,
    per_provider: Option<&str>,
) -> String {
    with_overrides(provider, global, per_provider, || {
        resolve_user_agent(provider)
            .to_str()
            .unwrap_or_default()
            .to_owned()
    })
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
    // Baseline: no overrides anywhere.
    let openai = with_overrides(LlmProvider::OpenAI, None, None, || {
        resolve_user_agent(LlmProvider::OpenAI)
    });
    // An OpenCodeGo-specific override must not change OpenAI resolution. The
    // ambient global override is cleared (and both variables are restored)
    // so the assertion is deterministic regardless of the test environment.
    let opencode_go_key = provider_override_env(LlmProvider::OpenCodeGo);
    let openai_with_opencode_override = with_env_vars(
        &[
            (AI_USER_AGENT_ENV, None),
            (opencode_go_key.as_str(), Some("opencode/1.0.0")),
        ],
        || resolve_user_agent(LlmProvider::OpenAI),
    );
    assert_eq!(openai.to_str().unwrap(), default_user_agent());
    assert_eq!(
        openai_with_opencode_override.to_str().unwrap(),
        default_user_agent()
    );
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
async fn build_hosted_client_sends_the_default_user_agent() {
    // The production builder, driven against the local capture server. `8.8.8.8`
    // is a public IP literal, so building performs no DNS and the test stays
    // offline; the pinned host only constrains requests to that host, while the
    // client-level default `User-Agent` applies to the loopback request here.
    let client = crate::ai::transport::build_hosted_client("8.8.8.8", Duration::from_secs(5))
        .await
        .unwrap_or_else(|error| panic!("cannot build hosted client: {error}"));
    let (address, captured) = spawn_capture_server();
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
        "the production hosted client must send the default User-Agent"
    );
}

#[tokio::test]
async fn ollama_production_client_sends_the_configured_user_agent() {
    // Build the real `OllamaChatClient` under the override, then drive its
    // production client against the local capture server. The env lock is
    // released before the request (no guard across `.await`).
    const CONFIGURED: &str = "breakdown-test/9.9.9 (ai-import)";
    let client = with_env_vars(&[(AI_USER_AGENT_ENV, Some(CONFIGURED))], || {
        crate::ai::OllamaChatClient::new(0, Duration::from_secs(5))
            .unwrap_or_else(|error| panic!("cannot build ollama client: {error}"))
    });
    let (address, captured) = spawn_capture_server();
    let response = client
        .http()
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
        Some(CONFIGURED),
        "the production Ollama client must send the configured User-Agent"
    );
}

#[tokio::test]
async fn catalog_production_client_sends_the_configured_user_agent() {
    // The catalog's shared client serves the Ollama regime and is built without
    // DNS; it must carry the configured agent like the chat clients do.
    const CONFIGURED: &str = "breakdown-test/8.8.8 (ai-import)";
    let catalog = with_env_vars(&[(AI_USER_AGENT_ENV, Some(CONFIGURED))], || {
        crate::ai::OpenAiCompatibleModelCatalog::new()
            .unwrap_or_else(|error| panic!("cannot build catalog: {error}"))
    });
    let (address, captured) = spawn_capture_server();
    let response = catalog
        .http()
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
        Some(CONFIGURED),
        "the production catalog client must send the configured User-Agent"
    );
}
