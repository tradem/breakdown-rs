// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: mimo-v2.5 (opencode-go)

//! In-process Typst adapter for PDF report rendering.
//!
//! This module implements the `ReportRenderer` port from `core` using
//! pinned `typst` + `typst-pdf` crates (ADR-022 D1).

pub mod locale;
pub mod typst_renderer;
