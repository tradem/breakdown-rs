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
    pub max_retries: u32,
}

const DEFAULT_MAX_CHUNKS: u32 = 128;
const DEFAULT_MAX_TOKENS: u32 = 8_192;
const DEFAULT_MAX_GLOBAL_CONCURRENCY: u32 = 16;
const DEFAULT_MAX_USER_CONCURRENCY: u32 = 2;

// These defaults are deliberately coupled to non-zero ceilings. This is a
// compile-time guard against accidentally shipping an unbounded worker.
const _: () = assert!(
    DEFAULT_MAX_CHUNKS > 0
        && DEFAULT_MAX_TOKENS > 0
        && DEFAULT_MAX_GLOBAL_CONCURRENCY > 0
        && DEFAULT_MAX_USER_CONCURRENCY > 0
);

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
        }
    }
}

impl AiImportBounds {
    /// Read bounded overrides from the environment. Invalid, zero, or
    /// excessively large values fall back to the safe default.
    pub fn from_env() -> Self {
        let defaults = Self::default();
        Self {
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
        }
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
