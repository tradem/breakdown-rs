// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4-flash (opencode-go)
// Co-authored-by: grok-4.5 (opencode-go)

//! Report rendering + archival infrastructure.
//!
//! This module implements the `ReportRenderer` and `ReportArchiveStorage`
//! ports from `core`, plus the durable job table, backup worker, and
//! enqueue triggers (schedule + `ShootingDayWrapped` reaction).

pub mod backup;
pub mod jobs;
pub mod locale;
pub mod storage;
pub mod triggers;
pub mod typst_renderer;

