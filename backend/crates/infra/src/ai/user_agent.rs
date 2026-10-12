// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (neuralwatt)

//! Descriptive, configurable `User-Agent` for the AI provider HTTP clients
//! (issue #521).
//!
//! Managed inference gateways in the opencode / OpenCode-Go ecosystem triage
//! requests on `User-Agent`: blank, generic, or library-default agents (the
//! reqwest fallback `reqwest/<version>`) are treated as bots and answered
//! with `403`. Every AI provider client therefore sends a descriptive, stable
//! agent string — `breakdown-rs-backend/<version> (ai-import)` by default.
//!
//! Operators can override it globally (`AI_IMPORT_USER_AGENT`) or per curated
//! provider (`AI_IMPORT_USER_AGENT_<PROVIDER>`, e.g.
//! `AI_IMPORT_USER_AGENT_OPENCODE_GO`) when a gateway demands its own format.
//! A `User-Agent` is not a credential, so no secret handling applies.
//!
//! The agent is additive transport metadata: it never changes the issue #170
//! redirect, DNS-pinning, or no-proxy policy of the clients it is attached to.

use breakdown_core::ai::LlmProvider;
use reqwest::header::HeaderValue;

/// Global override for the AI provider `User-Agent`.
pub(crate) const AI_USER_AGENT_ENV: &str = "AI_IMPORT_USER_AGENT";

/// Stable default agent: application name, crate version, subsystem.
const DEFAULT_AI_USER_AGENT: &str = concat!(
    "breakdown-rs-backend/",
    env!("CARGO_PKG_VERSION"),
    " (ai-import)"
);

/// The stable default agent string. Used by transport builders that do not
/// carry a provider (they send the global default rather than a generic
/// library agent).
pub(crate) const fn default_user_agent() -> &'static str {
    DEFAULT_AI_USER_AGENT
}

/// Environment variable that overrides the agent for one provider, e.g.
/// `AI_IMPORT_USER_AGENT_OPENCODE_GO` for `LlmProvider::OpenCodeGo`.
pub(crate) fn provider_override_env(provider: LlmProvider) -> String {
    let suffix = provider.as_str().to_ascii_uppercase().replace('-', "_");
    format!("{AI_USER_AGENT_ENV}_{suffix}")
}

/// Resolve the `User-Agent` for `provider`: per-provider env override, then
/// the global env override, then the stable default.
///
/// An empty or header-invalid override is ignored (the next source applies),
/// never a hard failure — a mistyped operator value must not break AI import.
pub(crate) fn resolve_user_agent(provider: LlmProvider) -> HeaderValue {
    std::env::var(provider_override_env(provider))
        .ok()
        .and_then(|raw| parse_header_value(&raw))
        .or_else(|| {
            std::env::var(AI_USER_AGENT_ENV)
                .ok()
                .and_then(|raw| parse_header_value(&raw))
        })
        .unwrap_or_else(|| HeaderValue::from_static(DEFAULT_AI_USER_AGENT))
}

fn parse_header_value(raw: &str) -> Option<HeaderValue> {
    let trimmed = raw.trim();
    if trimmed.is_empty() {
        return None;
    }
    HeaderValue::from_str(trimmed).ok()
}

#[cfg(test)]
#[path = "user_agent_tests.rs"]
mod user_agent_tests;
