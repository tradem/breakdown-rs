// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: gpt-5.6-luna (opencode-go)

use serde::{Deserialize, Serialize};
use utoipa::ToSchema;

/// Cost and concurrency ceilings for the import pipeline.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
pub struct AiImportBounds {
    pub max_chunks_per_script: u32,
    pub max_tokens_per_req: u32,
    pub max_concurrent_jobs_global: u32,
    pub max_concurrent_jobs_per_user: u32,
    pub max_document_bytes: u64,
    pub request_timeout_secs: u64,
    /// **Job-level** retry budget (issue #637): how often a job may be
    /// re-claimed after a retryable failure before it dead-letters.
    ///
    /// Unrelated to [`Self::max_attempt_retries`] since issue #871 — the two
    /// used to be one knob, which allowed `5 × 5 = 25` paid calls for a single
    /// chunk before anything surfaced.
    pub max_retries: u32,
    /// **In-attempt** retry budget (issue #871, D-C1): how often one chunk's
    /// provider call is retried inside a single attempt.
    ///
    /// Deliberately a second knob rather than a re-meaning of
    /// [`Self::max_retries`]: renaming a documented env var to fix a
    /// precedence bug would be churn without a beneficiary. `1 + 2 = 3`
    /// attempts per chunk is enough to tell a blip from an outage.
    pub max_attempt_retries: u32,
    /// Consecutive retryable provider failures for one `(provider, model)`
    /// pair that open the breaker (issue #871, D-A3).
    ///
    /// Counted per **pair across all jobs, chunks and replicas** — not per job
    /// and not per chunk — so independent observations accumulate toward one
    /// verdict. Only retryable provider failures count: a revoked key or an
    /// entitlement 4xx is permanent (#637) and must never turn one user's
    /// misconfiguration into an outage for everyone on the endpoint.
    pub breaker_failure_threshold: u32,
    /// Kill switch for the breaker (issue #871 rollout): with `false` the
    /// worker consults no health state and the claim predicate never filters,
    /// i.e. exactly the pre-#871 behaviour.
    pub breaker_enabled: bool,
    /// How long a job may sit **held** for one provider outage series before
    /// it dead-letters with the provider narrative (issue #871, D-C4).
    ///
    /// Measured from the first hold of the current series (the job's own
    /// `provider_hold_series_started_at`), so a flapping provider cannot reset
    /// the budget one probe at a time. Deliberately the same magnitude as the
    /// job-backoff cap (6 h).
    pub max_provider_hold_secs: u64,
}

/// How often the **hosted** client re-requests one call after a truncated answer
/// (issue #871, D-C2).
///
/// Declared here, not in the client, because the permit bound is an arithmetic
/// claim about **both** nested retry layers: `retry_bounded` retries the call and
/// the client retries the HTTP request inside it, so the worst case of one
/// attempt multiplies them. One source of truth means the bound cannot drift from
/// the clients it describes.
pub const HOSTED_INNER_RETRIES: u32 = 2;

/// The Ollama client's cap on re-requesting a malformed answer (issue #871,
/// D-C2). See [`HOSTED_INNER_RETRIES`].
pub const OLLAMA_INNER_RETRIES: u32 = 3;

/// The backoff cap `retry_bounded` sleeps between in-attempt retries
/// (`compute_backoff(attempt, 30 s)`), which the permit bound must include
/// because the loop sleeps while still holding the permit.
pub const MAX_ATTEMPT_BACKOFF_SECS: u64 = 30;

const DEFAULT_MAX_CHUNKS: u32 = 128;
const DEFAULT_MAX_TOKENS: u32 = 8_192;
const DEFAULT_MAX_GLOBAL_CONCURRENCY: u32 = 16;
const DEFAULT_MAX_USER_CONCURRENCY: u32 = 2;
const DEFAULT_MAX_ATTEMPT_RETRIES: u32 = 2;
const DEFAULT_BREAKER_FAILURE_THRESHOLD: u32 = 3;
const DEFAULT_MAX_PROVIDER_HOLD_SECS: u64 = 6 * 60 * 60;

// These defaults are deliberately coupled to non-zero ceilings. This is a
// compile-time guard against accidentally shipping an unbounded worker.
const _: () = assert!(
    DEFAULT_MAX_CHUNKS > 0
        && DEFAULT_MAX_TOKENS > 0
        && DEFAULT_MAX_GLOBAL_CONCURRENCY > 0
        && DEFAULT_MAX_USER_CONCURRENCY > 0
);

// Issue #871 (D-C1): the two retry layers must not multiply into a budget that
// cannot surface an outage. The invariant ties the **defaults** only —
// `consecutive_failures` counts per pair across all jobs, chunks and replicas,
// so a configured threshold above `1 + max_attempt_retries` still opens the
// breaker, just more slowly (one failure per chunk instead of up to three).
// `from_env` therefore bounds the values and warns instead of rejecting.
const _: () = assert!(DEFAULT_MAX_ATTEMPT_RETRIES + 1 >= DEFAULT_BREAKER_FAILURE_THRESHOLD);

impl Default for AiImportBounds {
    fn default() -> Self {
        Self {
            max_chunks_per_script: DEFAULT_MAX_CHUNKS,
            max_tokens_per_req: DEFAULT_MAX_TOKENS,
            max_concurrent_jobs_global: DEFAULT_MAX_GLOBAL_CONCURRENCY,
            max_concurrent_jobs_per_user: DEFAULT_MAX_USER_CONCURRENCY,
            max_document_bytes: 20 * 1024 * 1024,
            request_timeout_secs: 120,
            max_retries: 5,
            max_attempt_retries: DEFAULT_MAX_ATTEMPT_RETRIES,
            breaker_failure_threshold: DEFAULT_BREAKER_FAILURE_THRESHOLD,
            breaker_enabled: true,
            max_provider_hold_secs: DEFAULT_MAX_PROVIDER_HOLD_SECS,
        }
    }
}

impl AiImportBounds {
    /// Read bounded overrides from the environment. Invalid, zero, or
    /// excessively large values fall back to the safe default.
    pub fn from_env() -> Self {
        let defaults = Self::default();
        let mut bounds = Self {
            max_chunks_per_script: bounded_u32(
                "AI_IMPORT_MAX_CHUNKS_PER_SCRIPT",
                defaults.max_chunks_per_script,
                1,
                10_000,
            ),
            max_tokens_per_req: bounded_u32(
                "AI_IMPORT_MAX_TOKENS_PER_REQ",
                defaults.max_tokens_per_req,
                1,
                1_000_000,
            ),
            max_concurrent_jobs_global: bounded_u32(
                "AI_IMPORT_MAX_CONCURRENT_JOBS_GLOBAL",
                defaults.max_concurrent_jobs_global,
                1,
                1_000,
            ),
            max_concurrent_jobs_per_user: bounded_u32(
                "AI_IMPORT_MAX_CONCURRENT_JOBS_PER_USER",
                defaults.max_concurrent_jobs_per_user,
                1,
                100,
            ),
            max_document_bytes: bounded_u64(
                "AI_IMPORT_MAX_DOCUMENT_BYTES",
                defaults.max_document_bytes,
                1,
                1_000_000_000,
            ),
            request_timeout_secs: bounded_u64(
                "AI_IMPORT_REQUEST_TIMEOUT_SECS",
                defaults.request_timeout_secs,
                1,
                3_600,
            ),
            max_retries: bounded_u32("AI_IMPORT_MAX_RETRIES", defaults.max_retries, 0, 20),
            max_attempt_retries: bounded_u32(
                "AI_IMPORT_MAX_ATTEMPT_RETRIES",
                defaults.max_attempt_retries,
                0,
                10,
            ),
            breaker_failure_threshold: bounded_u32(
                "AI_IMPORT_BREAKER_FAILURE_THRESHOLD",
                defaults.breaker_failure_threshold,
                1,
                10,
            ),
            breaker_enabled: bounded_bool("AI_IMPORT_BREAKER_ENABLED", defaults.breaker_enabled),
            max_provider_hold_secs: bounded_u64(
                "AI_IMPORT_MAX_PROVIDER_HOLD_SECS",
                defaults.max_provider_hold_secs,
                60,
                7 * 24 * 60 * 60,
            ),
        };
        // Cross-field invariant (enforced by validate()): the per-user ceiling
        // must never exceed the global ceiling, or a per-user config could
        // admit more concurrent jobs than the global pool allows.
        bounds.max_concurrent_jobs_per_user = bounds
            .max_concurrent_jobs_per_user
            .min(bounds.max_concurrent_jobs_global);
        bounds
    }

    /// Issue #871 (D-C1): whether the configured breaker threshold is higher
    /// than one chunk can contribute, i.e. whether a single chunk can no longer
    /// open the breaker alone.
    ///
    /// A threshold above `1 + max_attempt_retries` is a legitimate operator
    /// choice — `consecutive_failures` counts per **pair across all jobs,
    /// chunks and replicas**, so the breaker still opens, just more slowly.
    /// This is therefore reported, not rejected: the caller logs it once at
    /// startup. It is a pure predicate rather than a `tracing::warn!` here
    /// because `core` carries no logging dependency (AGENTS.md §1) — the
    /// composition root owns the log line.
    pub const fn breaker_threshold_exceeds_attempt_budget(&self) -> bool {
        self.breaker_enabled && self.breaker_failure_threshold > self.max_attempt_retries + 1
    }

    /// The analytic worst case of **one attempt** across both nested retry
    /// layers (issue #871, D-C2).
    ///
    /// ```
    /// (1 + max_attempt_retries) × (1 + inner_retries) × request_timeout_secs
    ///   + max_attempt_retries × MAX_ATTEMPT_BACKOFF_SECS
    /// ```
    ///
    /// The multiplication is the point: one *attempt* is not one request. The
    /// outer layer retries the call `1 + max_attempt_retries` times, and the
    /// client re-requests a truncated/malformed answer `1 + inner_retries` times
    /// *inside* each of those. `retry_bounded` also sleeps between attempts while
    /// still holding the concurrency permit, so the backoff is part of the window
    /// a waiting job occupies capacity for.
    ///
    /// With the defaults: hosted = 3 × 3 × 120 s + 2 × 30 s = **19 min**,
    /// Ollama = 3 × 4 × 120 s + 2 × 30 s = **25 min**. Before #871 the outer
    /// layer alone was 6 × 120 s + 5 × 30 s = 14.5 min — the split knob shortened
    /// it, the client-internal retries lengthen it, and this function is what
    /// makes both statements checkable instead of remembered.
    #[must_use]
    pub const fn attempt_worst_case_secs(&self, inner_retries: u32) -> u64 {
        (self.max_attempt_retries as u64 + 1)
            .saturating_mul(inner_retries as u64 + 1)
            .saturating_mul(self.request_timeout_secs)
            .saturating_add(
                (self.max_attempt_retries as u64).saturating_mul(MAX_ATTEMPT_BACKOFF_SECS),
            )
    }

    /// Worst-case token budget for one script before provider-side spend
    /// controls are considered.
    pub const fn worst_case_tokens(&self) -> u64 {
        self.max_chunks_per_script as u64 * self.max_tokens_per_req as u64
    }

    pub fn validate(&self) -> Result<(), &'static str> {
        if self.max_chunks_per_script == 0
            || self.max_tokens_per_req == 0
            || self.max_concurrent_jobs_global == 0
            || self.max_concurrent_jobs_per_user == 0
        {
            return Err("AI import bounds must be non-zero");
        }
        if self.max_concurrent_jobs_per_user > self.max_concurrent_jobs_global {
            return Err("per-user AI concurrency cannot exceed global concurrency");
        }
        Ok(())
    }
}

#[cfg(test)]
#[path = "bounds_tests.rs"]
mod bounds_tests;

fn bounded_u32(name: &str, default: u32, min: u32, max: u32) -> u32 {
    std::env::var(name)
        .ok()
        .and_then(|value| value.parse::<u32>().ok())
        .filter(|value| (*value >= min) && (*value <= max))
        .unwrap_or(default)
}

fn bounded_u64(name: &str, default: u64, min: u64, max: u64) -> u64 {
    std::env::var(name)
        .ok()
        .and_then(|value| value.parse::<u64>().ok())
        .filter(|value| (*value >= min) && (*value <= max))
        .unwrap_or(default)
}

/// Read a boolean flag with the same accepted spellings as the rest of the
/// AI-import switches (`AI_IMPORT_ENABLED`): `true`/`1`/`yes` and
/// `false`/`0`/`no`, case-insensitive. Anything else keeps the default.
fn bounded_bool(name: &str, default: bool) -> bool {
    match std::env::var(name).ok().as_deref() {
        Some(value) if value.eq_ignore_ascii_case("true") => true,
        Some("1") => true,
        Some(value) if value.eq_ignore_ascii_case("yes") => true,
        Some(value) if value.eq_ignore_ascii_case("false") => false,
        Some("0") => false,
        Some(value) if value.eq_ignore_ascii_case("no") => false,
        _ => default,
    }
}
