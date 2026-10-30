// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3 (neuralwatt)

//! `reset-dev-data` — safe, repeatable dev data reset (issue #770).
//!
//! Maintenance binary, **never** an HTTP route: it deletes business data (and,
//! at level `business`, the whole event store) while preserving the
//! configuration, so AI imports can be replayed for integration verification.
//! The engine lives in `infra::dev_reset`; this binary only parses arguments,
//! renders the report and sets the exit code.
//!
//! Runbook: `docs/operations/runbooks.md` → "Dev data reset (issue #770)".
//! Wrapper: `scripts/reset-dev-data.sh` (drives the level-`business` phases
//! around the SierraDB volume drop).
//!
//! A CLI's output *is* its product, so `print_stdout`/`print_stderr` are
//! allowed here (the workspace denies them to keep server logs on `tracing`).

#![allow(clippy::print_stdout, clippy::print_stderr)]

use std::io::Write;
use std::path::PathBuf;

use anyhow::{Context, Result, bail};
use infra::dev_reset::{self, ResetLevel, ResetOptions, ResetPhase};

const USAGE: &str = "\
reset-dev-data — dev-only data reset that preserves the configuration (issue #770)

USAGE:
  reset-dev-data --level <imports|business> --env dev [OPTIONS]

LEVELS:
  imports    Undo the AI imports: delete the job rows (the upload dedup
             blocker), purge the payload objects and remove the aggregates the
             imports created through real domain commands. Keeps every other
             business aggregate, the AI config, the credentials and the roles.
  business   Wipe all business data including the event store, then replay the
             configuration streams (ai_config, settings, membership). Driven in
             phases by scripts/reset-dev-data.sh, because SierraDB can only be
             emptied by removing its data volume.

OPTIONS:
  --phase <all|export|wipe|replay|verify>   Phase (default: all; level business
                                            requires an explicit phase)
  --dry-run                 Print the complete keep/reset plan, write nothing
  --yes                     Skip the interactive target confirmation
  --no-backup               Do not take a backup (must be typed explicitly)
  --skip-payload-purge      Continue even when the AI payload objects cannot be
                            purged (their handles live only in the job rows, so
                            the objects become unreachable)
  --backup-dir <path>       Backup directory (default: backups/reset-<utc>)
  --env dev                 Required acknowledgement that this is a dev stack
  -h, --help                Print this help

SAFETY:
  Refuses unless APP_ENV is development/unset, REQUIRE_IN_TRANSIT_TLS is not
  true, and DATABASE_URL/SIERRADB_URL both point at loopback hosts.
";

struct ParsedArgs {
    level: Option<ResetLevel>,
    phase: Option<ResetPhase>,
    dry_run: bool,
    assume_yes: bool,
    backup: bool,
    skip_payload_purge: bool,
    backup_dir: Option<PathBuf>,
    dev_ack: bool,
    help: bool,
}

impl Default for ParsedArgs {
    fn default() -> Self {
        Self {
            level: None,
            phase: None,
            dry_run: false,
            assume_yes: false,
            backup: true,
            skip_payload_purge: false,
            backup_dir: None,
            dev_ack: false,
            help: false,
        }
    }
}

fn parse_args() -> Result<ParsedArgs> {
    let mut parsed = ParsedArgs::default();
    let mut args = std::env::args().skip(1);
    while let Some(arg) = args.next() {
        match arg.as_str() {
            "--level" => {
                let value = args.next().context("--level requires a value")?;
                parsed.level = Some(
                    ResetLevel::parse(&value)
                        .with_context(|| format!("unknown --level {value:?}"))?,
                );
            }
            "--phase" => {
                let value = args.next().context("--phase requires a value")?;
                parsed.phase = Some(
                    ResetPhase::parse(&value)
                        .with_context(|| format!("unknown --phase {value:?}"))?,
                );
            }
            "--backup-dir" => {
                parsed.backup_dir = Some(PathBuf::from(
                    args.next().context("--backup-dir requires a path")?,
                ));
            }
            "--dry-run" => parsed.dry_run = true,
            "--yes" => parsed.assume_yes = true,
            "--no-backup" => parsed.backup = false,
            "--skip-payload-purge" => parsed.skip_payload_purge = true,
            "--env" => {
                let value = args.next().context("--env requires a value")?;
                if value != "dev" {
                    bail!("--env {value:?} is not supported: the reset tooling only runs in dev");
                }
                parsed.dev_ack = true;
            }
            "-h" | "--help" => parsed.help = true,
            other => bail!("unknown argument {other:?}\n\n{USAGE}"),
        }
    }
    Ok(parsed)
}

/// Reads the confirmation line from stdin (the operator retypes the target).
///
/// The expected value is printed, not implied: the engine compares against the
/// normalised `host/database` of the connection URL, which the operator cannot
/// know without being told (issue #770 review).
fn read_confirmation(expected: &str) -> Result<String> {
    print!("retype the target `{expected}` to confirm: ");
    if let Err(error) = std::io::stdout().flush() {
        // A failed flush means the prompt may not have rendered; the read below
        // still blocks, so warn and continue instead of aborting the reset.
        eprintln!("warning: could not flush the confirmation prompt: {error}");
    }
    let mut line = String::new();
    std::io::stdin()
        .read_line(&mut line)
        .context("read the confirmation from stdin")?;
    Ok(line.trim().to_string())
}

#[tokio::main]
async fn main() -> Result<()> {
    let parsed = parse_args()?;
    if parsed.help {
        print!("{USAGE}");
        return Ok(());
    }

    let Some(level) = parsed.level else {
        bail!("--level is required\n\n{USAGE}");
    };
    if !parsed.dev_ack {
        bail!("--env dev is required (the reset tooling never runs against production)\n\n{USAGE}");
    }

    let phase = match (level, parsed.phase) {
        (_, Some(phase)) => phase,
        (ResetLevel::Imports, None) => ResetPhase::All,
        (ResetLevel::Business, None) => bail!(
            "level business requires an explicit --phase: the event store can only be emptied by \
             removing its data volume, so the phases are driven by scripts/reset-dev-data.sh \
             business\n\n{USAGE}"
        ),
    };
    if level == ResetLevel::Imports && phase != ResetPhase::All {
        bail!("level imports runs as one phase: drop --phase (or pass --phase all)\n\n{USAGE}");
    }

    // Logs go to stderr; the report is the stdout product. A second init (a
    // test harness, an embedding caller) is not an error — say so and continue.
    if let Err(error) = tracing_subscriber::fmt()
        .with_writer(std::io::stderr)
        .with_target(false)
        .try_init()
    {
        eprintln!("warning: tracing subscriber not installed: {error}");
    }

    let backup_dir = parsed
        .backup_dir
        .unwrap_or_else(|| dev_reset::backup::default_dir(chrono::Utc::now()));

    let mut options = ResetOptions {
        level,
        phase,
        dry_run: parsed.dry_run,
        assume_yes: parsed.assume_yes,
        dev_ack: parsed.dev_ack,
        backup: parsed.backup,
        skip_payload_purge: parsed.skip_payload_purge,
        backup_dir,
        confirmation: None,
    };

    // `verify` is read-only, so it never asks for a confirmation; the engine
    // enforces the same rule (issue #770 review).
    if !options.dry_run && !options.assume_yes && phase != ResetPhase::Verify {
        let expected = dev_reset::DevEnvironment::from_env().target_label();
        let typed = read_confirmation(&expected)?;
        options.confirmation = Some(typed);
    }

    let report = dev_reset::run(options).await?;
    print!("{}", report.render());
    println!("{}", report.audit_line());
    if !report.is_success() {
        bail!(
            "reset finished with {} failure(s) — see the report above",
            report.failures.len()
        );
    }
    Ok(())
}
