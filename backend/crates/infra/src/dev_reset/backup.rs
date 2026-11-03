// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3 (neuralwatt)

//! Backup directory for a reset run (issue #770).
//!
//! A backup is taken **by default**; `--no-backup` has to be typed explicitly.
//! The directory layout is deliberately boring so an operator can read it with
//! `jq`/`less` and restore by hand:
//!
//! ```text
//! backups/reset-<timestamp>/
//!   manifest.json          what ran, against which target, which files exist
//!   keep-list.json         verbatim keep-list event export (level business)
//!   replay-report.json     what the replay actually appended (level business)
//!   pricing.json           ai_model_pricing rows (exported, never deleted)
//!   imports.json           AI import jobs + mapping rows (level imports)
//!   postgres.dump          pg_dump of the whole database (written by the script)
//!   sierradb-data.tgz      event-store volume tarball (written by the script)
//! ```
//!
//! The `business` wipe refuses to run when a backup was requested and the
//! manifest is missing — the backup is the safety net, not a formality.
//!
//! `replay-report.json` is the *receipt* of the destructive half (issue #810):
//! it records what the replay appended, bound to the export it consumed, so a
//! later run can never mistake a post-loss export (10 streams, 0 events) for
//! the original one.

use std::path::{Path, PathBuf};

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

use super::events::KeepListExport;

/// Format version of the manifest document.
pub const MANIFEST_FORMAT_VERSION: u32 = 1;

/// Format version of the replay record.
pub const REPLAY_FORMAT_VERSION: u32 = 1;

/// File name of the manifest inside a backup directory.
pub const MANIFEST_FILE: &str = "manifest.json";

/// File name of the replay record inside a backup directory (issue #810).
pub const REPLAY_REPORT_FILE: &str = "replay-report.json";

/// What a backup directory contains and why.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct BackupManifest {
    pub format_version: u32,
    pub created_at: DateTime<Utc>,
    pub level: String,
    pub phase: String,
    pub database_target: String,
    pub event_store_target: String,
    pub keep_rows: i64,
    pub reset_rows: i64,
    /// Files this process wrote (relative to the backup directory).
    pub files: Vec<String>,
    /// `postgres.dump` / `sierradb-data.tgz` are produced by the wrapper script;
    /// this records whether they are expected for this run.
    pub external_artifacts: Vec<String>,
}

impl BackupManifest {
    /// Renders the human-readable index the operator reads first.
    pub fn render(&self) -> String {
        let mut out = String::new();
        out.push_str(&format!("backup of {} / {}\n", self.level, self.phase));
        out.push_str(&format!("created:      {}\n", self.created_at));
        out.push_str(&format!("postgres:     {}\n", self.database_target));
        out.push_str(&format!("event store:  {}\n", self.event_store_target));
        out.push_str(&format!(
            "rows:         {} keep / {} business\n",
            self.keep_rows, self.reset_rows
        ));
        out.push_str("files:\n");
        for file in &self.files {
            out.push_str(&format!("  {file}\n"));
        }
        if !self.external_artifacts.is_empty() {
            out.push_str("written by scripts/reset-dev-data.sh:\n");
            for file in &self.external_artifacts {
                out.push_str(&format!("  {file}\n"));
            }
        }
        out
    }
}

/// Creates the backup directory (idempotent).
pub fn prepare_dir(dir: &Path) -> std::io::Result<()> {
    std::fs::create_dir_all(dir)
}

/// Writes a JSON document into the backup directory and returns its path.
pub fn write_json<T: Serialize>(dir: &Path, name: &str, value: &T) -> std::io::Result<PathBuf> {
    prepare_dir(dir)?;
    let path = dir.join(name);
    let body = serde_json::to_vec_pretty(value).map_err(std::io::Error::other)?;
    std::fs::write(&path, body)?;
    Ok(path)
}

/// Reads a JSON document from the backup directory.
pub fn read_json<T: for<'de> Deserialize<'de>>(dir: &Path, name: &str) -> std::io::Result<T> {
    let path = dir.join(name);
    let body = std::fs::read(&path)?;
    serde_json::from_slice(&body).map_err(std::io::Error::other)
}

/// `true` when the directory holds a manifest (i.e. a backup was taken).
pub fn manifest_exists(dir: &Path) -> bool {
    dir.join(MANIFEST_FILE).is_file()
}

/// What the replay of one keep stream actually appended.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ReplayStreamRecord {
    pub stream_id: String,
    /// Events the keep-list export carries for this stream.
    pub expected: usize,
    /// Events the replay appended for this stream.
    pub appended: usize,
}

/// The receipt of a replay: what went back into the fresh event store.
///
/// Written by `--phase replay` and compared by `--phase verify` (issue #810).
/// `keep_list_created_at` binds the receipt to the export it consumed: a
/// *later* export (e.g. one taken after a failed run emptied the store) can
/// never be verified against the receipt of the original replay.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ReplayReport {
    pub format_version: u32,
    pub created_at: DateTime<Utc>,
    pub keep_list_created_at: DateTime<Utc>,
    pub expected_events: usize,
    pub appended_events: usize,
    pub streams: Vec<ReplayStreamRecord>,
}

impl ReplayReport {
    /// The receipt for a replay that appended `appended_events` of `export`.
    pub fn new(export: &KeepListExport, appended_events: usize) -> Self {
        Self {
            format_version: REPLAY_FORMAT_VERSION,
            created_at: Utc::now(),
            keep_list_created_at: export.created_at,
            expected_events: export.event_count(),
            appended_events,
            streams: export
                .streams
                .iter()
                .map(|stream| ReplayStreamRecord {
                    stream_id: stream.stream_id.clone(),
                    expected: stream.events.len(),
                    appended: stream.events.len(),
                })
                .collect(),
        }
    }

    /// Never a silent success: everything this receipt claims must match the
    /// export it describes (issue #810).
    ///
    /// Deliberately pure so the comparison is unit-tested without a database.
    pub fn mismatches(&self, export: &KeepListExport) -> Vec<String> {
        let mut mismatches = Vec::new();
        if self.format_version != REPLAY_FORMAT_VERSION {
            mismatches.push(format!(
                "replay-report.json has format version {} but this binary verifies version {}",
                self.format_version, REPLAY_FORMAT_VERSION
            ));
        }
        if self.keep_list_created_at != export.created_at {
            mismatches.push(format!(
                "replay-report.json belongs to the keep-list export created at {} but {} was \
                 created at {} — a post-loss export must never be verified against an earlier \
                 replay",
                self.keep_list_created_at,
                super::business::KEEP_LIST_FILE,
                export.created_at
            ));
        }
        if self.expected_events != export.event_count() {
            mismatches.push(format!(
                "the replay expected {} event(s) but the export carries {}",
                self.expected_events,
                export.event_count()
            ));
        }
        if self.appended_events != self.expected_events {
            mismatches.push(format!(
                "the replay appended {} of {} event(s) — the keep-list is not restored",
                self.appended_events, self.expected_events
            ));
        }
        for stream in &export.streams {
            let record = self
                .streams
                .iter()
                .find(|record| record.stream_id == stream.stream_id);
            match record {
                None => mismatches.push(format!(
                    "replay-report.json has no record for keep stream {} ({} event(s) expected)",
                    stream.stream_id,
                    stream.events.len()
                )),
                Some(record) => {
                    if record.appended != record.expected {
                        mismatches.push(format!(
                            "the replay appended {} of {} event(s) for keep stream {}",
                            record.appended, record.expected, record.stream_id
                        ));
                    }
                    if record.expected != stream.events.len() {
                        mismatches.push(format!(
                            "replay-report.json expects {} event(s) for keep stream {} but the \
                             export carries {}",
                            record.expected,
                            stream.stream_id,
                            stream.events.len()
                        ));
                    }
                }
            }
        }
        mismatches
    }

    /// Human-readable summary line for the report.
    pub fn render(&self) -> String {
        format!(
            "replay record: {} of {} event(s) over {} stream(s), keep-list from {}",
            self.appended_events,
            self.expected_events,
            self.streams.len(),
            self.keep_list_created_at
        )
    }
}

/// The default backup root: `backend/backups/reset-<timestamp>`.
///
/// `CARGO_MANIFEST_DIR` is `crates/infra`, so the workspace `backend/`
/// directory is two levels up — the same anchor the scripts use.
pub fn default_dir(now: DateTime<Utc>) -> PathBuf {
    let backend = Path::new(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .and_then(Path::parent)
        .map(Path::to_path_buf)
        .unwrap_or_else(|| PathBuf::from("."));
    backend
        .join("backups")
        .join(format!("reset-{}", super::timestamp_slug(now)))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn scratch_dir() -> PathBuf {
        let dir =
            std::env::temp_dir().join(format!("breakdown-reset-test-{}", uuid::Uuid::now_v7()));
        prepare_dir(&dir).expect("create scratch dir");
        dir
    }

    fn manifest() -> BackupManifest {
        BackupManifest {
            format_version: MANIFEST_FORMAT_VERSION,
            created_at: Utc::now(),
            level: "business".to_string(),
            phase: "export".to_string(),
            database_target: "localhost/breakdown".to_string(),
            event_store_target: "127.0.0.1:9090".to_string(),
            keep_rows: 7,
            reset_rows: 812,
            files: vec!["keep-list.json".to_string()],
            external_artifacts: vec!["postgres.dump".to_string()],
        }
    }

    #[test]
    fn manifest_round_trips_and_is_detected() {
        let dir = scratch_dir();
        let expected = manifest();
        assert!(!manifest_exists(&dir));
        write_json(&dir, MANIFEST_FILE, &expected).expect("write manifest");
        assert!(manifest_exists(&dir));
        let parsed: BackupManifest = read_json(&dir, MANIFEST_FILE).expect("read manifest");
        assert_eq!(parsed, expected);
        // Test cleanup only; a leftover temp directory must not fail the suite.
        if let Err(error) = std::fs::remove_dir_all(&dir) {
            eprintln!("warning: could not remove {}: {error}", dir.display());
        }
    }

    #[test]
    fn manifest_render_names_the_artifacts() {
        let rendered = manifest().render();
        assert!(rendered.contains("business / export"));
        assert!(rendered.contains("localhost/breakdown"));
        assert!(rendered.contains("127.0.0.1:9090"));
        assert!(rendered.contains("7 keep / 812 business"));
        assert!(rendered.contains("postgres.dump"));
    }

    #[test]
    fn default_dir_sits_under_backend_backups() {
        let dir = default_dir(Utc::now());
        let text = dir.to_string_lossy().to_string();
        assert!(text.contains("backups"), "{text}");
        assert!(text.contains("reset-"), "{text}");
        let parent = dir.parent().expect("has a parent");
        assert_eq!(
            parent.file_name().and_then(|name| name.to_str()),
            Some("backups")
        );
        assert!(
            dir.parent()
                .and_then(Path::parent)
                .map(|path| path.ends_with("backend"))
                .unwrap_or(false),
            "backup root must be backend/backups, got {}",
            dir.display()
        );
    }

    fn keep_export(events_per_stream: &[usize]) -> KeepListExport {
        KeepListExport {
            format_version: super::super::events::EXPORT_FORMAT_VERSION,
            created_at: Utc::now(),
            database_target: "localhost/breakdown".to_string(),
            streams: events_per_stream
                .iter()
                .enumerate()
                .map(|(index, events)| super::super::events::ExportedStream {
                    stream_id: format!("ai_config-0199a0c0-0000-7000-8000-{index:012}"),
                    category: "ai_config".to_string(),
                    events: (0..*events)
                        .map(|version| super::super::events::ExportedEvent {
                            stream_id: format!("ai_config-0199a0c0-0000-7000-8000-{index:012}"),
                            event_name: "AiConfigUpdated".to_string(),
                            event_id: uuid::Uuid::now_v7(),
                            stream_version: version as u64,
                            timestamp_millis: 1_700_000_000_000,
                            payload_hex: "a0".to_string(),
                            metadata_hex: String::new(),
                        })
                        .collect(),
                })
                .collect(),
        }
    }

    /// The receipt of a complete replay round-trips and reports no mismatch.
    #[test]
    fn a_complete_replay_record_matches_its_export() {
        let export = keep_export(&[2, 1]);
        let record = ReplayReport::new(&export, export.event_count());
        assert!(
            record.mismatches(&export).is_empty(),
            "{:?}",
            record.mismatches(&export)
        );
        assert_eq!(record.expected_events, 3);
        assert_eq!(record.keep_list_created_at, export.created_at);
        assert!(record.render().contains("3 of 3 event(s)"));

        let dir = scratch_dir();
        write_json(&dir, REPLAY_REPORT_FILE, &record).expect("write replay record");
        let parsed: ReplayReport = read_json(&dir, REPLAY_REPORT_FILE).expect("read back");
        assert_eq!(parsed, record);
        // Test cleanup only; a leftover temp directory must not fail the suite.
        if let Err(error) = std::fs::remove_dir_all(&dir) {
            eprintln!("warning: could not remove {}: {error}", dir.display());
        }
    }

    /// Defect 2 of issue #810: a replay that appended nothing must never read
    /// as a success.
    #[test]
    fn a_replay_that_appended_nothing_is_a_mismatch() {
        let export = keep_export(&[2, 1]);
        let record = ReplayReport::new(&export, 0);
        let mismatches = record.mismatches(&export);
        assert!(
            mismatches
                .iter()
                .any(|line| line.contains("appended 0 of 3")),
            "{mismatches:?}"
        );
    }

    /// A receipt that describes a *different* export must not validate: that is
    /// how a post-loss export would otherwise pass as the original one.
    #[test]
    fn a_record_of_another_export_is_a_mismatch() {
        let export = keep_export(&[1]);
        let other = keep_export(&[1, 1]);
        let record = ReplayReport::new(&other, other.event_count());
        let mismatches = record.mismatches(&export);
        assert!(
            mismatches
                .iter()
                .any(|line| line.contains("belongs to the keep-list export created at")),
            "{mismatches:?}"
        );
        assert!(
            mismatches
                .iter()
                .any(|line| line.contains("expected 2 event(s) but the export carries 1")),
            "{mismatches:?}"
        );
    }

    #[test]
    fn reading_a_missing_document_is_an_error_not_a_default() {
        let dir = scratch_dir();
        let result: std::io::Result<BackupManifest> = read_json(&dir, MANIFEST_FILE);
        assert!(result.is_err());
        // Test cleanup only; a leftover temp directory must not fail the suite.
        if let Err(error) = std::fs::remove_dir_all(&dir) {
            eprintln!("warning: could not remove {}: {error}", dir.display());
        }
    }
}
