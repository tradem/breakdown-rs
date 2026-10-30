// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3 (neuralwatt)

//! Dev-only data reset (issue #770) — safe, repeatable, configuration-preserving.
//!
//! ## What this is for
//!
//! Replaying AI script imports for integration verification needs a data set
//! reset: the upload dedup (`ai_import.ai_import_job` is unique on
//! `(user_id, dedup_key)`) turns a re-upload of the same document into a no-op,
//! and "just create a new season" cannot scope an import (the target is the
//! ambient `X-Active-Block`). This module implements the reset without giving up
//! the configuration (AI config incl. the Decision Model, credential bindings,
//! roles) that a full wipe would destroy.
//!
//! ## Levels
//!
//! * [`ResetLevel::Imports`] — undo the imports: delete the job rows (the dedup
//!   blocker), purge the payload objects, and remove the aggregates the imports
//!   created **through real domain commands** (children first, see
//!   [`imports::DELETE_ORDER`]).
//! * [`ResetLevel::Business`] — the sledgehammer: export the keep-list
//!   (`ai_config`, `settings`, `membership`) verbatim, wipe every business
//!   projection, the operational bookkeeping and the business buckets, and
//!   replay the keep-list. The event store itself can only be wiped from
//!   outside the process (SierraDB 0.3.1 has no delete command), so the
//!   `business` level is split into the [`ResetPhase`]s that
//!   `scripts/reset-dev-data.sh` drives around the volume drop.
//!
//! ## Safety (non-negotiable, issue #770)
//!
//! * **No HTTP route.** This is a local maintenance binary; a reset endpoint
//!   would be a footgun even behind dev-auth.
//! * **Prod refusal** in [`guard`]: explicit `--env dev`, `APP_ENV`,
//!   `REQUIRE_IN_TRANSIT_TLS` and loopback-only connection targets.
//! * **`--dry-run`** prints the whole [`plan::ResetPlan`] and writes nothing.
//! * **Backup by default**, into `backups/reset-<timestamp>/`; `--no-backup`
//!   has to be typed explicitly.
//! * **Confirmation** naming the target host/database unless `--yes` is passed.
//! * **Closed classification** in [`classification`]: a new aggregate cannot
//!   silently default into "keep".
//! * **Audit line** ([`ResetReport::audit_line`]) with mode, target,
//!   keep/reset counts and the backup path.

pub mod backup;
pub mod business;
pub mod classification;
pub mod events;
pub mod guard;
pub mod imports;
pub mod plan;

use std::path::PathBuf;

use anyhow::{Context as _, Result, bail};
use kameo_es::command_service::CommandService;
use redis::aio::MultiplexedConnection;
use sqlx::postgres::PgPoolOptions;
use sqlx::{PgPool, Row};

pub use classification::{AggregateCategory, AggregateClass};
pub use guard::{DevEnvironment, Refusal};
pub use plan::{ResetLevel, ResetPhase, ResetPlan};

/// Everything the run needs from the command line, resolved and typed.
#[derive(Debug, Clone)]
pub struct ResetOptions {
    pub level: ResetLevel,
    pub phase: ResetPhase,
    pub dry_run: bool,
    /// `--yes`: skip the interactive target confirmation.
    pub assume_yes: bool,
    /// `--env dev`: the explicit development acknowledgement.
    pub dev_ack: bool,
    /// Backups are taken unless `--no-backup` was typed.
    pub backup: bool,
    /// `--skip-payload-purge`: continue when the AI payload objects cannot be
    /// purged. Without it a failed purge aborts the run **before** the job rows
    /// (whose handles are the only way to find the objects) are deleted.
    pub skip_payload_purge: bool,
    pub backup_dir: PathBuf,
    /// What the operator typed at the confirmation prompt.
    pub confirmation: Option<String>,
}

/// The connected resources a reset run works with.
pub struct Context {
    pub pool: PgPool,
    pub connection: MultiplexedConnection,
    pub command_service: CommandService,
    pub database_target: String,
    pub event_store_target: String,
}

/// What a run did, in printable form.
#[derive(Debug, Clone, Default)]
pub struct ResetReport {
    pub headline: String,
    pub lines: Vec<String>,
    /// Non-fatal problems: a partial reset must be visible, not swallowed.
    pub failures: Vec<String>,
    /// Aggregates whose delete command succeeded. The import provenance of the
    /// others is deliberately **kept** so a re-run can still find them
    /// (issue #770 review).
    pub deleted_aggregates: Vec<uuid::Uuid>,
    pub backup_path: Option<PathBuf>,
    pub dry_run: bool,
}

impl ResetReport {
    /// `true` when nothing failed — the binary turns `false` into exit code 1.
    pub fn is_success(&self) -> bool {
        self.failures.is_empty()
    }

    /// The audit line (issue #770): mode, target, counts, backup path.
    pub fn audit_line(&self) -> String {
        format!(
            "reset-dev-data audit: {} | backup: {} | failures: {}",
            self.headline,
            self.backup_path
                .as_ref()
                .map(|path| path.display().to_string())
                .unwrap_or_else(|| "none".to_string()),
            self.failures.len()
        )
    }

    pub fn render(&self) -> String {
        let mut out = String::new();
        out.push_str(&format!("== reset-dev-data: {} ==\n", self.headline));
        for line in &self.lines {
            out.push_str(&format!("  {line}\n"));
        }
        if let Some(path) = &self.backup_path {
            out.push_str(&format!("  backup: {}\n", path.display()));
        }
        if !self.failures.is_empty() {
            out.push_str("\n  FAILURES\n");
            for failure in &self.failures {
                out.push_str(&format!("    ! {failure}\n"));
            }
        }
        if self.dry_run {
            out.push_str("\n  (dry run — nothing was written)\n");
        }
        out
    }
}

/// Runs a reset: guard, plan, dry-run, confirmation, execution.
pub async fn run(options: ResetOptions) -> Result<ResetReport> {
    let environment = DevEnvironment::from_env();
    guard::check(&environment, options.dev_ack)
        .map_err(|refusal| anyhow::anyhow!(refusal.reason()))?;

    let database_target = environment.target_label();
    let event_store_target = event_store_label(&environment.sierradb_url);

    let pool = PgPoolOptions::new()
        .max_connections(4)
        .connect(&environment.database_url)
        .await
        .with_context(|| format!("connect PostgreSQL at {database_target}"))?;
    // The plan is PostgreSQL-only on purpose: `--dry-run` must work with
    // SierraDB stopped (issue #770 review), so the event store is connected
    // only after the dry-run return.
    let plan = ResetPlan::build(
        &pool,
        options.level,
        options.phase,
        database_target.clone(),
        event_store_target.clone(),
    )
    .await
    .context("build the reset plan")?;

    if options.dry_run {
        let mut report = ResetReport {
            headline: format!(
                "{} / {} — dry run",
                plan.level.as_str(),
                plan.phase.as_str()
            ),
            dry_run: true,
            ..ResetReport::default()
        };
        report.lines.push(plan.render());
        report.lines.push(match plan.imports_scope {
            Some(scope) => format!(
                "would delete {} imported aggregate(s) plus up to {} episode candidate(s), from {} \
                 provenance row(s) — the {} reset-category row(s) stay untouched",
                scope.imported_aggregates,
                scope.episode_candidates,
                scope.provenance_rows,
                plan.reset_rows()
            ),
            None => format!("would touch {} business rows", plan.reset_rows()),
        });
        return Ok(report);
    }

    // `verify` is read-only: it never needs a confirmation, so it also runs
    // unattended (issue #770 review).
    if !options.assume_yes && plan.phase != ResetPhase::Verify {
        let typed = options.confirmation.as_deref().unwrap_or_default().trim();
        if typed != plan.database_target {
            bail!(
                "refusing to reset: retype the target `{}` at the confirmation prompt, or pass --yes",
                plan.database_target
            );
        }
    }

    let client = redis::Client::open(environment.sierradb_url.clone())
        .with_context(|| format!("open SierraDB client at {event_store_target}"))?;
    let connection = client
        .get_multiplexed_async_connection()
        .await
        .with_context(|| format!("connect SierraDB at {event_store_target}"))?;
    let command_service = CommandService::new(connection.clone());

    let mut context = Context {
        pool,
        connection,
        command_service,
        database_target,
        event_store_target,
    };

    let report = match options.level {
        ResetLevel::Imports => imports::execute(&mut context, &plan, &options).await?,
        ResetLevel::Business => business::execute(&mut context, &plan, &options).await?,
    };

    tracing::info!("{}", report.audit_line());
    Ok(report)
}

/// `host:port` of the event store, credentials never included.
fn event_store_label(url: &str) -> String {
    let host = guard::url_host(url).unwrap_or_else(|| "?".to_string());
    let port = url
        .split_once("://")
        .and_then(|(_, rest)| rest.split(['/', '?']).next())
        .and_then(|authority| {
            authority
                .rsplit_once('@')
                .map_or(Some(authority), |(_, h)| Some(h))
        })
        .and_then(|host_port| host_port.rsplit_once(':'))
        .map(|(_, port)| port.to_string());
    match port {
        Some(port) => format!("{host}:{port}"),
        None => host,
    }
}

/// Small helper for the backup + report paths: ISO-ish UTC stamp without a
/// dependency on a formatting crate beyond `chrono`.
pub fn timestamp_slug(now: chrono::DateTime<chrono::Utc>) -> String {
    now.format("%Y%m%dT%H%M%SZ").to_string()
}

/// Convenience for the SQL helpers: count of a static statement.
pub async fn count(pool: &PgPool, sql: &'static str) -> Result<i64> {
    let row = sqlx::query(sql).fetch_one(pool).await?;
    Ok(row.try_get::<i64, _>(0)?)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn event_store_label_hides_credentials_and_keeps_the_port() {
        assert_eq!(
            event_store_label("redis://127.0.0.1:9090/?protocol=resp3"),
            "127.0.0.1:9090"
        );
        assert_eq!(
            event_store_label("rediss://user:secret@localhost:9091/"),
            "localhost:9091"
        );
        assert_eq!(event_store_label("redis://localhost/"), "localhost");
        assert_eq!(event_store_label("nonsense"), "?");
    }

    #[test]
    fn audit_line_carries_mode_target_counts_and_backup() {
        let report = ResetReport {
            headline: "level imports / phase all | target localhost/breakdown | keep 7 rows | reset 812 rows".to_string(),
            backup_path: Some(PathBuf::from("backups/reset-20260101T000000Z")),
            ..ResetReport::default()
        };
        let line = report.audit_line();
        assert!(line.contains("level imports"));
        assert!(line.contains("localhost/breakdown"));
        assert!(line.contains("backups/reset-20260101T000000Z"));
        assert!(line.contains("failures: 0"));
        assert!(report.is_success());
    }

    #[test]
    fn report_renders_failures_and_dry_run_marker() {
        let report = ResetReport {
            headline: "dry".to_string(),
            lines: vec!["line".to_string()],
            failures: vec!["DeleteScene abc failed".to_string()],
            deleted_aggregates: Vec::new(),
            backup_path: None,
            dry_run: true,
        };
        let rendered = report.render();
        assert!(rendered.contains("FAILURES"));
        assert!(rendered.contains("DeleteScene abc failed"));
        assert!(rendered.contains("dry run"));
        assert!(!report.is_success());
    }

    #[test]
    fn timestamp_slug_is_filename_safe() {
        let slug = timestamp_slug(
            chrono::DateTime::parse_from_rfc3339("2026-01-02T03:04:05Z")
                .unwrap()
                .with_timezone(&chrono::Utc),
        );
        assert_eq!(slug, "20260102T030405Z");
        assert!(!slug.contains(':'));
    }
}
