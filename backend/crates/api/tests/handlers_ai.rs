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

#[path = "handler_ai_import_sse.rs"]
mod handler_ai_import_sse;

#[path = "handler_ai_import_apply_sse.rs"]
mod handler_ai_import_apply_sse;

// Issue #912: the one case that composes both apply-identity HTTP surfaces
// through PostgreSQL. Env-gated (`AI_IMPORT_PG_TESTS=1`) so it skips without
// starting a container; the "Testcontainers integration tests" CI job sets it.
#[path = "handler_ai_import_pg_composition.rs"]
mod handler_ai_import_pg_composition;

// Issue #942 W4: the provider-health + budget read (caller-owned credential,
// tenant isolation, no tenant material on the wire).
#[path = "handler_ai_provider_health.rs"]
mod handler_ai_provider_health;

#[path = "handler_audit.rs"]
mod handler_audit;
