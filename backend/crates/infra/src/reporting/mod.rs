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

#[cfg(test)]
#[path = "storage_contract_test.rs"]
mod storage_contract_test;

pub use backup::{
    BackupWorkerConfig, EmptyReportDataLoader, ReportBackupWorker, ReportDataLoader,
    SceneShootReportDataLoader, spawn_backup_worker,
};
pub use jobs::PgReportArchivalQueue;
pub use storage::{
    MemoryReportArchiveStorage, OpenDalReportArchiveStorage, StorageRole, external_key, sha256_hex,
    staging_key,
};
pub use triggers::{
    ScheduleConfig, enqueue_for_day, spawn_schedule_ticker, spawn_wrap_archival_saga,
};
pub use typst_renderer::TypstReportRenderer;
