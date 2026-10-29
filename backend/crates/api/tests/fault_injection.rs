// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (neuralwatt)

//! Test-support integration-test harness (issue #631): the `test-support`-only
//! E2E seeding machinery — the #443 fault latch and the #748 stored AI-import
//! preview fixture.
//!
//! The harness is gated by `#![cfg(feature = "test-support")]`, so the whole
//! crate (helpers included) disappears when the feature is off. The shared
//! `common` module is declared ONCE here and imported by the case files
//! (`use crate::common;`): clippy's `duplicate_mod` lint (deny) rejects a
//! per-case `mod common;`.

#![cfg(feature = "test-support")]

#[path = "common/mod.rs"]
pub mod common;

#[path = "fault_injection_test.rs"]
mod fault_injection_test;

// Issue #748: the stored AI-import preview fixture ships under the same
// compile-time gate (it is test-support-only E2E seeding machinery, like the
// fault latch above).
#[path = "ai_import_fixture_test.rs"]
mod ai_import_fixture_test;
