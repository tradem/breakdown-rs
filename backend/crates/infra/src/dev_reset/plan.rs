// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3 (neuralwatt)

//! The reset plan — what a run would keep, delete and purge (issue #770).
//!
//! A plan is always built **before** anything is written, and `--dry-run`
//! prints it and stops. The plan is therefore the single description of what
//! the tooling does: the execution paths in [`super::imports`] and
//! [`super::business`] consume the same category registry
//! ([`AggregateCategory`]), so a plan can never claim something the run does
//! not do.

use sqlx::PgPool;

use super::classification::{AggregateCategory, AggregateClass};

/// How much the reset removes.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ResetLevel {
    /// Light: undo the AI imports (jobs, payloads, imported aggregates) and
    /// leave the rest of the business data alone.
    Imports,
    /// Sledgehammer: wipe every business projection, the whole event store and
    /// the business object buckets, then replay the configuration streams.
    Business,
}

impl ResetLevel {
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::Imports => "imports",
            Self::Business => "business",
        }
    }

    pub fn parse(value: &str) -> Option<Self> {
        match value {
            "imports" => Some(Self::Imports),
            "business" => Some(Self::Business),
            _ => None,
        }
    }
}

/// The step of a level. `imports` is a single step; `business` is split because
/// the event store can only be wiped from outside the process (SierraDB 0.3.1
/// has no selective or wholesale delete command — the data volume must go).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ResetPhase {
    /// The whole level in one run (`imports` only).
    All,
    /// Level `business`: export the keep-list into the backup directory.
    Export,
    /// Level `business`: clear the read model and the business buckets. The
    /// event store must already be empty (checked).
    Wipe,
    /// Level `business`: replay the exported keep-list events verbatim.
    Replay,
    /// Level `business`: assert the post-conditions against the running API.
    Verify,
}

impl ResetPhase {
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::All => "all",
            Self::Export => "export",
            Self::Wipe => "wipe",
            Self::Replay => "replay",
            Self::Verify => "verify",
        }
    }

    pub fn parse(value: &str) -> Option<Self> {
        match value {
            "all" => Some(Self::All),
            "export" => Some(Self::Export),
            "wipe" => Some(Self::Wipe),
            "replay" => Some(Self::Replay),
            "verify" => Some(Self::Verify),
            _ => None,
        }
    }
}

/// Row count of one aggregate category's projection table.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct CategoryCount {
    pub category: AggregateCategory,
    pub rows: i64,
}

/// Row count of an operational table the reset clears.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct TableCount {
    pub table: &'static str,
    pub rows: i64,
}

/// What a level-`imports` run would actually delete.
///
/// Derived from the import provenance, not from the total business row count:
/// `imports` only removes the aggregates an import created, so the
/// reset-category sum would overstate it (issue #770 review).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ImportsScope {
    /// Rows in `ai_import.projection_ai_import_mapping`.
    pub provenance_rows: i64,
    /// Distinct aggregates the provenance points at (the deletable kinds).
    pub imported_aggregates: i64,
    /// Episodes the block/recency heuristic would attribute to the imports.
    pub episode_candidates: i64,
}

/// An object-storage bucket in the reset scope.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BucketTarget {
    pub name: String,
    pub detail: String,
}

/// Everything a run would do, in printable form.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ResetPlan {
    pub level: ResetLevel,
    pub phase: ResetPhase,
    pub database_target: String,
    pub event_store_target: String,
    pub keep: Vec<CategoryCount>,
    pub reset: Vec<CategoryCount>,
    pub tables: Vec<TableCount>,
    pub buckets: Vec<BucketTarget>,
    pub notes: Vec<String>,
    /// Provenance-derived scope for level `imports`; `None` for `business`.
    pub imports_scope: Option<ImportsScope>,
}

/// Operational (non-projection) tables the reset clears, with their static
/// count statements. Order matters for the business wipe: children and
/// restrict-referencing rows first.
pub const BOOKKEEPING_TABLES: &[(&str, &str)] = &[
    (
        "report_ops.report_job",
        "SELECT count(*) FROM report_ops.report_job",
    ),
    (
        "ai_import.projection_ai_import_mapping",
        "SELECT count(*) FROM ai_import.projection_ai_import_mapping",
    ),
    (
        "ai_import.ai_import_job",
        "SELECT count(*) FROM ai_import.ai_import_job",
    ),
    (
        "ai_import.ai_import_job_attempt",
        "SELECT count(*) FROM ai_import.ai_import_job_attempt",
    ),
    (
        "ai_import.ai_payload_cleanup",
        "SELECT count(*) FROM ai_import.ai_payload_cleanup",
    ),
    (
        "ai_import.concurrency_permit",
        "SELECT count(*) FROM ai_import.concurrency_permit",
    ),
    (
        "ai_import.projection_ai_payload_gc_run",
        "SELECT count(*) FROM ai_import.projection_ai_payload_gc_run",
    ),
    (
        "projection_photo_gc_run",
        "SELECT count(*) FROM projection_photo_gc_run",
    ),
    ("projection_audit", "SELECT count(*) FROM projection_audit"),
    (
        "projection_dead_letter",
        "SELECT count(*) FROM projection_dead_letter",
    ),
    (
        "sierradb_event_checkpoints",
        "SELECT count(*) FROM sierradb_event_checkpoints",
    ),
];

impl ResetPlan {
    /// Counts every category and operational table, then assembles the plan.
    pub async fn build(
        pool: &PgPool,
        level: ResetLevel,
        phase: ResetPhase,
        database_target: String,
        event_store_target: String,
    ) -> Result<Self, sqlx::Error> {
        let mut keep = Vec::new();
        let mut reset = Vec::new();
        for category in AggregateCategory::ALL {
            let rows: i64 = sqlx::query_scalar(category.count_sql())
                .fetch_one(pool)
                .await?;
            let entry = CategoryCount { category, rows };
            match category.class() {
                AggregateClass::Keep => keep.push(entry),
                AggregateClass::Reset => reset.push(entry),
            }
        }

        let mut tables = Vec::new();
        for (table, sql) in BOOKKEEPING_TABLES {
            let rows: i64 = sqlx::query_scalar(*sql).fetch_one(pool).await?;
            tables.push(TableCount { table, rows });
        }

        let imports_scope = match level {
            ResetLevel::Imports => Some(count_imports_scope(pool).await?),
            ResetLevel::Business => None,
        };

        Ok(Self {
            level,
            phase,
            database_target,
            event_store_target,
            keep,
            reset,
            tables,
            buckets: bucket_targets(),
            notes: notes_for(level),
            imports_scope,
        })
    }

    /// Total business rows the plan touches (reset categories only).
    pub fn reset_rows(&self) -> i64 {
        self.reset.iter().map(|entry| entry.rows).sum()
    }

    /// Total keep rows (configuration).
    pub fn keep_rows(&self) -> i64 {
        self.keep.iter().map(|entry| entry.rows).sum()
    }

    /// The operator-facing plan text.
    pub fn render(&self) -> String {
        let mut out = String::new();
        out.push_str("== reset-dev-data plan ==\n");
        out.push_str(&format!(
            "level: {}   phase: {}\n",
            self.level.as_str(),
            self.phase.as_str()
        ));
        out.push_str(&format!(
            "postgres:    {} ({} keep rows, {} business rows)\n",
            self.database_target,
            self.keep_rows(),
            self.reset_rows()
        ));
        out.push_str(&format!("event store: {}\n", self.event_store_target));

        out.push_str("\nKEEP — configuration, exported and replayed (never reset)\n");
        for entry in &self.keep {
            out.push_str(&format!(
                "  {:<5} {:<17} {:>7} rows   {}\n",
                entry.category.class().as_str(),
                entry.category.as_str(),
                entry.rows,
                entry.category.projection_table()
            ));
        }

        out.push_str("\nRESET — business data\n");
        for entry in &self.reset {
            out.push_str(&format!(
                "  {:<5} {:<17} {:>7} rows   {}\n",
                entry.category.class().as_str(),
                entry.category.as_str(),
                entry.rows,
                entry.category.projection_table()
            ));
        }

        if let Some(scope) = &self.imports_scope {
            out.push_str("\nIMPORT SCOPE (provenance-derived — this level deletes only these)\n");
            out.push_str(&format!(
                "  {:>7} provenance row(s)\n  {:>7} imported aggregate(s)\n  {:>7} episode candidate(s) (block + recency heuristic, #763)\n",
                scope.provenance_rows, scope.imported_aggregates, scope.episode_candidates
            ));
        }

        out.push_str("\nOPERATIONAL TABLES\n");
        for entry in &self.tables {
            out.push_str(&format!("  {:<42} {:>7} rows\n", entry.table, entry.rows));
        }

        out.push_str("\nOBJECT STORAGE\n");
        for bucket in &self.buckets {
            out.push_str(&format!("  {:<24} {}\n", bucket.name, bucket.detail));
        }

        out.push_str("\nNOTES\n");
        for note in &self.notes {
            out.push_str(&format!("  - {note}\n"));
        }
        out
    }
}

/// Counts what level `imports` would remove, from the import provenance.
async fn count_imports_scope(pool: &PgPool) -> Result<ImportsScope, sqlx::Error> {
    let provenance_rows: i64 =
        sqlx::query_scalar("SELECT count(*) FROM ai_import.projection_ai_import_mapping")
            .fetch_one(pool)
            .await?;
    let imported_aggregates: i64 = sqlx::query_scalar(
        r#"
        SELECT count(DISTINCT aggregate_id)
        FROM ai_import.projection_ai_import_mapping
        WHERE aggregate_kind IN ('scene', 'character', 'piece', 'outfit', 'shooting_day',
                                 'scene_shoot')
        "#,
    )
    .fetch_one(pool)
    .await?;
    // Same heuristic the execution path uses (the import → episode provenance is
    // not persisted yet, #763).
    let episode_candidates: i64 = sqlx::query_scalar(
        r#"
        SELECT count(*)
        FROM projection_episode e
        WHERE e.block_id IN (SELECT block_id FROM ai_import.ai_import_job WHERE block_id IS NOT NULL)
          AND e.updated_at >= (SELECT min(created_at) FROM ai_import.ai_import_job)
        "#,
    )
    .fetch_one(pool)
    .await?;
    Ok(ImportsScope {
        provenance_rows,
        imported_aggregates,
        episode_candidates,
    })
}

/// The object-storage buckets that hold business data (issue #770).
fn bucket_targets() -> Vec<BucketTarget> {
    let photo_bucket = std::env::var("S3_BUCKET").unwrap_or_else(|_| "costume-photos".to_string());
    let payload_bucket =
        std::env::var("AI_PAYLOAD_S3_BUCKET").unwrap_or_else(|_| "ai-import-payloads".to_string());
    let staging_bucket = std::env::var("REPORT_BACKUP_STAGING_BUCKET")
        .or_else(|_| std::env::var("S3_BUCKET"))
        .unwrap_or_else(|_| "costume-photos".to_string());

    vec![
        BucketTarget {
            name: photo_bucket,
            detail: "photo bytes (SSE-C; purged through the photo port when Vault is reachable)"
                .to_string(),
        },
        BucketTarget {
            name: payload_bucket,
            detail: "AI import source documents and preview payloads (level imports and business)"
                .to_string(),
        },
        BucketTarget {
            name: staging_bucket,
            detail: "rendered report staging objects (prefix REPORT_BACKUP_STAGING_PREFIX)"
                .to_string(),
        },
    ]
}

fn notes_for(level: ResetLevel) -> Vec<String> {
    match level {
        ResetLevel::Imports => vec![
            "aggregates are removed through real domain commands, children first: \
             scene_shoot → scene → shooting_day → outfit → piece → character → episode"
                .to_string(),
            "import-created episodes are resolved heuristically from the job's block_id plus \
             created_at recency — the import → episode provenance is not persisted yet (#763)"
                .to_string(),
            "the AI job rows and their dedup keys are deleted, so re-uploading the same document \
             enqueues a fresh job (202 + new id) instead of returning the old one"
                .to_string(),
            "ai_config, settings and membership streams are untouched".to_string(),
        ],
        ResetLevel::Business => vec![
            "the event store can only be wiped by removing its data volume: run \
             scripts/reset-dev-data.sh business, which stops the API, backs up, drops \
             backend_sierradb_dev_data and drives the phases in order"
                .to_string(),
            "keep-list streams (ai_config, settings, membership) are exported before the wipe and \
             replayed verbatim afterwards, so the projectors rebuild the keep projections"
                .to_string(),
            "ai_model_pricing is exported for the backup but deliberately kept — the cost \
             snapshot depends on it"
                .to_string(),
            "Vault is never touched: the settings → Vault credential bindings stay resolvable"
                .to_string(),
        ],
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn plan() -> ResetPlan {
        ResetPlan {
            level: ResetLevel::Imports,
            phase: ResetPhase::All,
            database_target: "localhost/breakdown".to_string(),
            event_store_target: "127.0.0.1:9090".to_string(),
            keep: vec![CategoryCount {
                category: AggregateCategory::AiConfig,
                rows: 1,
            }],
            reset: vec![CategoryCount {
                category: AggregateCategory::Scene,
                rows: 42,
            }],
            tables: vec![TableCount {
                table: "ai_import.ai_import_job",
                rows: 5,
            }],
            buckets: bucket_targets(),
            notes: notes_for(ResetLevel::Imports),
            imports_scope: Some(ImportsScope {
                provenance_rows: 380,
                imported_aggregates: 147,
                episode_candidates: 4,
            }),
        }
    }

    #[test]
    fn level_and_phase_parse_round_trip() {
        for level in [ResetLevel::Imports, ResetLevel::Business] {
            assert_eq!(ResetLevel::parse(level.as_str()), Some(level));
        }
        for phase in [
            ResetPhase::All,
            ResetPhase::Export,
            ResetPhase::Wipe,
            ResetPhase::Replay,
            ResetPhase::Verify,
        ] {
            assert_eq!(ResetPhase::parse(phase.as_str()), Some(phase));
        }
        assert_eq!(ResetLevel::parse("everything"), None);
        assert_eq!(ResetPhase::parse(""), None);
    }

    #[test]
    fn render_names_every_section_and_count() {
        let rendered = plan().render();
        for needle in [
            "reset-dev-data plan",
            "level: imports",
            "phase: all",
            "localhost/breakdown",
            "127.0.0.1:9090",
            "KEEP",
            "RESET",
            "OPERATIONAL TABLES",
            "OBJECT STORAGE",
            "NOTES",
            "ai_config",
            "scene",
            "ai_import.ai_import_job",
        ] {
            assert!(
                rendered.contains(needle),
                "missing {needle:?} in\n{rendered}"
            );
        }
        assert_eq!(plan().keep_rows(), 1);
        assert_eq!(plan().reset_rows(), 42);
        // The imports scope is rendered from the provenance, not from the
        // reset-category sum.
        assert!(rendered.contains("IMPORT SCOPE"));
        assert!(rendered.contains("147 imported aggregate(s)"));
        assert!(rendered.contains("4 episode candidate(s)"));
    }

    /// Every category is listed exactly once across the two sections.
    #[test]
    fn render_covers_every_category_once() {
        let mut plan = plan();
        plan.keep = Vec::new();
        plan.reset = AggregateCategory::ALL
            .iter()
            .map(|category| CategoryCount {
                category: *category,
                rows: 0,
            })
            .collect();
        let rendered = plan.render();
        for category in AggregateCategory::ALL {
            let needle = format!("{:<17}", category.as_str());
            assert_eq!(
                rendered.matches(&needle).count(),
                1,
                "category {} rendered more than once",
                category.as_str()
            );
        }
    }

    #[test]
    fn business_notes_point_at_the_volume_reset() {
        let notes = notes_for(ResetLevel::Business).join("\n");
        assert!(notes.contains("scripts/reset-dev-data.sh"));
        assert!(notes.contains("ai_model_pricing"));
        assert!(notes.contains("Vault"));
    }
}
