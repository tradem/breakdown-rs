// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (neuralwatt)

//! Consolidated AI-import/audit handler integration-test harness (issue #631).
//!
//! The AI import suites are the heaviest handler tests; grouping them keeps
//! them out of the general handler harness while still linking once. They
//! share the single `common` test-support module declared here.

mod common;

#[path = "handler_ai_import_authz.rs"]
mod handler_ai_import_authz;

#[path = "handler_ai_import_ports.rs"]
mod handler_ai_import_ports;

#[path = "handler_audit.rs"]
mod handler_audit;
