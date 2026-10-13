// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (neuralwatt)

//! Consolidated contract/coverage integration-test harness (issue #631).
//!
//! Groups the OpenAPI drift check, route/bundle coverage, the RFC 9457 error
//! surface and the problem-code golden file. The error-surface case file uses
//! the shared `common` module declared here.

mod common;

#[path = "bundle_coverage.rs"]
mod bundle_coverage;

#[path = "openapi_drift.rs"]
mod openapi_drift;

#[path = "problem_golden.rs"]
mod problem_golden;

#[path = "route_coverage.rs"]
mod route_coverage;

#[path = "http_error_surface.rs"]
mod http_error_surface;
