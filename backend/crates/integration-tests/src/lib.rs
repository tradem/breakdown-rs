// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024 Breakdown RS Contributors

//! Black-box integration tests for the `breakdown-rs` backend.
//!
//! This crate is intentionally **dev-only**: it consumes only the public API of
//! [`breakdown_core`] and [`infra`] and exercises the system against real
//! external resources (e.g. a PostgreSQL container managed by `testcontainers`).
//!
//! No production code should ever depend on this crate. Shared helpers that are
//! useful outside this crate live behind the `testing` feature of `infra` (and
//! `core` if needed).
//!
//! The canonical test pattern is:
//!
//! ```text
//! spawn resource → seed via public command API → assert via public query API → drop guards
//! ```
//!
//! See `tests/smoke_postgres_harness.rs` for the Postgres harness template.
