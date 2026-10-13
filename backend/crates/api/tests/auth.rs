// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (neuralwatt)

//! Consolidated auth/TLS integration-test harness (issue #631).
//!
//! Each case file is `#[path]`-included as a module so the full dependency
//! graph is linked once for the whole group instead of once per file. Cargo
//! discovers only the harnesses declared in `crates/api/Cargo.toml`
//! (`autotests = false`); the case files themselves are not test targets.

#[path = "auth_authorization.rs"]
mod auth_authorization;

#[path = "auth_jwks.rs"]
mod auth_jwks;

#[path = "auth_mod.rs"]
mod auth_mod;

#[path = "tls_config.rs"]
mod tls_config;
