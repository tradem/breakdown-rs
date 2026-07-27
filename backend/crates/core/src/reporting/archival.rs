// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4-flash (opencode-go)
// Co-authored-by: grok-4.5 (opencode-go)

//! Report-archival queue port (enqueue side) and shared request/result DTOs.
//!
//! The durable job table itself is **infrastructure state** (see design D2):
//! it holds no business truth and no domain query path reads from it. This
//! port only exposes the operational enqueue/lookup surface the API and
//! triggers need.
use async_trait::async_trait;
use serde::{Deserialize, Serialize};
use thiserror::Error;
use utoipa::ToSchema;
use uuid::Uuid;
use crate::shared::ShootingDayId;
use super::{ReportKind, ReportLocale};
/// Opaque identifier of a durable report-archival job.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize, ToSchema)]
#[serde(transparent)]
pub struct ReportJobId(pub Uuid);
impl ReportJobId {
    /// Generate a new UUIDv7 job id.
    pub fn new() -> Self {
        Self(Uuid::now_v7())
    }
}
impl Default for ReportJobId {
    fn default() -> Self {
        Self::new()
impl std::fmt::Display for ReportJobId {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}", self.0)
/// How the archival job was triggered (operational provenance only).
#[serde(rename_all = "snake_case")]
pub enum ArchivalTrigger {
    /// Periodic schedule ticker.
    Schedule,
    /// Reaction to `ShootingDayWrapped`.
    Wrapped,
    /// Manual "archive now" HTTP remediation.
    Manual,
impl ArchivalTrigger {
    /// Stable string form used in audit fields (not the dedup key).
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Schedule => "schedule",
            Self::Wrapped => "wrapped",
            Self::Manual => "manual",
        }
/// Snapshot identity component of the dedup key.
///
/// All triggers for the same logical snapshot share this identity so a manual
/// press after a wrap (or schedule) is a no-op via the same dedup key.
#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize, ToSchema)]
pub struct SnapshotIdentity(String);
impl SnapshotIdentity {
    /// Default snapshot identity for the current archival generation of a day.
    ///
    /// v1 uses a stable `"current"` token so wrap/schedule/manual share the
    /// same dedup key for a given (kind, day, locale, template_version).
    pub fn current() -> Self {
        Self("current".into())
    /// Construct from a validated non-empty string.
    pub fn new(s: impl Into<String>) -> Self {
        Self(s.into())
    /// Borrow as str.
    pub fn as_str(&self) -> &str {
        &self.0
/// Request to enqueue one archival job for a single report kind.
#[derive(Debug, Clone, Serialize, Deserialize, ToSchema)]
pub struct EnqueueArchivalRequest {
    /// Report kind to archive.
    pub kind: ReportKind,
    /// Shooting day whose report is archived.
    pub shooting_day_id: ShootingDayId,
    /// Locale for the render.
    pub locale: ReportLocale,
    /// Template version (normally [`super::storage::TEMPLATE_VERSION`]).
    pub template_version: String,
    /// Snapshot identity for the dedup key.
    pub snapshot_identity: SnapshotIdentity,
    /// Trigger provenance (audit only; not part of the dedup key).
    pub trigger: ArchivalTrigger,
impl EnqueueArchivalRequest {
    /// Compose the deterministic dedup key.
    /// Format: `{kind}|{shooting_day_id}|{snapshot}|{locale}|{template_version}`
    pub fn dedup_key(&self) -> String {
        format!(
            "{}|{}|{}|{}|{}",
            self.kind,
            self.shooting_day_id.0,
            self.snapshot_identity.as_str(),
            self.locale.as_str(),
            self.template_version
        )
/// Result of an enqueue attempt.
pub struct EnqueueArchivalResult {
    /// Job id (existing or newly created).
    pub job_id: ReportJobId,
    /// `true` when a pre-existing job was returned (dedup hit).
    pub already_enqueued: bool,
    /// Current operational status of the job.
    pub status: ReportJobStatus,
/// Operational status of a report-archival job.
/// This is **not** business state — it records only whether a backup was
/// requested / staged / accepted by the provider.
pub enum ReportJobStatus {
    /// Waiting to be claimed by a worker.
    Pending,
    /// Claimed by a worker; render/staging in progress.
    Claimed,
    /// PDF written to durable staging; external upload pending/in progress.
    Staged,
    /// External upload in flight.
    Uploading,
    /// Provider accepted the object; staging retention may apply.
    Succeeded,
    /// Transient failure; will retry until max_retries.
    Failed,
    /// Retries exhausted; requires operator action.
    DeadLetter,
impl ReportJobStatus {
    /// Parse from the static DB string form.
    pub fn parse(s: &str) -> Option<Self> {
        match s {
            "pending" => Some(Self::Pending),
            "claimed" => Some(Self::Claimed),
            "staged" => Some(Self::Staged),
            "uploading" => Some(Self::Uploading),
            "succeeded" => Some(Self::Succeeded),
            "failed" => Some(Self::Failed),
            "dead_letter" => Some(Self::DeadLetter),
            _ => None,
    /// Static DB string form.
            Self::Pending => "pending",
            Self::Claimed => "claimed",
            Self::Staged => "staged",
            Self::Uploading => "uploading",
            Self::Succeeded => "succeeded",
            Self::Failed => "failed",
            Self::DeadLetter => "dead_letter",
/// Errors from the archival queue / worker surface.
/// Never carries PDF bytes or provider credentials.
#[derive(Error, Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
pub enum ReportArchivalError {
    #[error("report archival: shooting day not found")]
    ShootingDayNotFound,
    #[error("report archival: conflict: {detail}")]
    Conflict { detail: String },
    #[error("report archival: storage error: {detail}")]
    Storage { detail: String },
    #[error("report archival: render error: {detail}")]
    Render { detail: String },
    #[error("report archival: internal error: {detail}")]
    Internal { detail: String },
/// Port for enqueuing report-archival jobs (API + triggers).
/// Implementations live in `infra` against a dedicated PostgreSQL schema
/// (separate from business projections). No domain query path reads job
/// state as business truth.
#[async_trait]
pub trait ReportArchivalQueue: Send + Sync {
    /// Enqueue a job, or return the existing one when the dedup key matches.
    async fn enqueue(
        &self,
        req: EnqueueArchivalRequest,
    ) -> Result<EnqueueArchivalResult, ReportArchivalError>;
    /// Look up a job by id (operational status only).
    async fn get(
        job_id: ReportJobId,
    ) -> Result<Option<EnqueueArchivalResult>, ReportArchivalError>;
#[cfg(test)]
mod tests {
    use super::*;
    use crate::reporting::ReportKind;
    #[test]
    fn dedup_key_is_stable_across_triggers() {
        let day = ShootingDayId(Uuid::now_v7());
        let base = |trigger: ArchivalTrigger| EnqueueArchivalRequest {
            kind: ReportKind::Dispo,
            shooting_day_id: day,
            locale: ReportLocale::de_de(),
            template_version: "1.0.0".into(),
            snapshot_identity: SnapshotIdentity::current(),
            trigger,
        };
        let a = base(ArchivalTrigger::Wrapped).dedup_key();
        let b = base(ArchivalTrigger::Manual).dedup_key();
        let c = base(ArchivalTrigger::Schedule).dedup_key();
        assert_eq!(a, b);
        assert_eq!(b, c);
        assert!(a.contains("dispo"));
        assert!(a.contains("1.0.0"));
        assert!(a.contains("de-DE"));
        assert!(a.contains("current"));
    fn job_status_roundtrip() {
        for s in [
            ReportJobStatus::Pending,
            ReportJobStatus::Claimed,
            ReportJobStatus::Staged,
            ReportJobStatus::Uploading,
            ReportJobStatus::Succeeded,
            ReportJobStatus::Failed,
            ReportJobStatus::DeadLetter,
        ] {
            assert_eq!(ReportJobStatus::parse(s.as_str()), Some(s));
        assert_eq!(ReportJobStatus::parse("nope"), None);
    fn archival_error_has_no_byte_payload() {
        let err = ReportArchivalError::Storage {
            detail: "timeout".into(),
        assert!(!err.to_string().contains("%PDF"));
