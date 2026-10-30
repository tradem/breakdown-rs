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
//!   pricing.json           ai_model_pricing rows (exported, never deleted)
//!   imports.json           AI import jobs + mapping rows (level imports)
//!   postgres.dump          pg_dump of the whole database (written by the script)
//!   sierradb-data.tgz      event-store volume tarball (written by the script)
//! ```
//!
//! The `business` wipe refuses to run when a backup was requested and the
//! manifest is missing — the backup is the safety net, not a formality.

use std::path::{Path, PathBuf};

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

/// Format version of the manifest document.
pub const MANIFEST_FORMAT_VERSION: u32 = 1;

/// File name of the manifest inside a backup directory.
pub const MANIFEST_FILE: &str = "manifest.json";

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
