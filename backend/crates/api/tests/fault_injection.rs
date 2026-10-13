// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (neuralwatt)

//! Fault-injection integration-test harness (issue #631).
//!
//! The case file is gated by `#![cfg(feature = "test-support")]` and declares
//! its own `common` module inside that gate, so no root `mod common;` is
//! needed here — the module (and its helper) simply disappears when the
//! feature is off.

#[path = "fault_injection_test.rs"]
mod fault_injection_test;
