// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors

//! `kameo_es` write adapters implementing the `core` command ports.
//!
//! Every adapter owns a clone of the shared `CommandService`. It translates a
//! `core` command into `SceneAggregate::execute(...)` / `ExpectedVersion` calls
//! against SierraDB and maps the reply back to `DomainError`.

use breakdown_core::calculation::aggregate::CalculationAggregate;
use breakdown_core::calculation::commands::{
    AddCalculationItem, CreateCalculation, MarkItemAsPaid, MarkItemAsUnpaid, RemoveCalculationItem,
    UpdateCalculationItem, UpdateHeaderInfo,
};
use breakdown_core::calculation::ports::CalculationCommands;
use breakdown_core::character::aggregate::CharacterAggregate;
use breakdown_core::character::commands::{CreateCharacter, UpdateContactInfo, UpdateMeasurements};
use breakdown_core::character::ports::CharacterCommands;
use breakdown_core::costume::aggregate::CostumeAggregate;
use breakdown_core::costume::commands::{
    AddDetail, AssignCostumeToCharacter, CreateCostume, LinkPhoto, RemoveDetail, UnassignCostume,
    UnlinkPhoto, UpdateCostumeNotes,
};
use breakdown_core::costume::ports::CostumeCommands;
use breakdown_core::error::DomainError;
use breakdown_core::scene::aggregate::SceneAggregate;
use breakdown_core::scene::commands::{
    AssignCharacter, CreateScene, RemoveCharacter, UpdateSceneDetails,
};
use breakdown_core::scene::ports::SceneCommands;
use breakdown_core::shared::AggregateVersion;
use kameo_es::command_service::{CommandService, ExecuteExt, ExecuteResult};
use kameo_es::error::ExecuteError;
use sierradb_client::{CurrentVersion, ExpectedVersion};
use uuid::Uuid;

/// Command adapter for the Scene aggregate.
#[derive(Clone, Debug)]
pub struct SceneCommandsImpl {
    cmd_service: CommandService,
}

impl SceneCommandsImpl {
    pub fn new(cmd_service: CommandService) -> Self {
        Self { cmd_service }
    }
}

impl SceneCommands for SceneCommandsImpl {
    async fn create(&self, cmd: CreateScene) -> Result<(Uuid, AggregateVersion), DomainError> {
        let id = cmd.id;
        let result = SceneAggregate::execute(&self.cmd_service, id, cmd)
            .expected_version(ExpectedVersion::Empty)
            .await;
        map_executed(id, result)
    }

    async fn update_details(
        &self,
        cmd: UpdateSceneDetails,
    ) -> Result<AggregateVersion, DomainError> {
        let id = cmd.id;
        let version = cmd.version;
        check_nonzero_version(version)?;
        let result = SceneAggregate::execute(&self.cmd_service, id, cmd)
            .expected_version(ExpectedVersion::Exact(domain_to_stream(version).unwrap()))
            .await;
        map_version_only(result)
    }

    async fn assign_character(
        &self,
        cmd: AssignCharacter,
    ) -> Result<AggregateVersion, DomainError> {
        let id = cmd.id;
        let version = cmd.version;
        check_nonzero_version(version)?;
        let result = SceneAggregate::execute(&self.cmd_service, id, cmd)
            .expected_version(ExpectedVersion::Exact(domain_to_stream(version).unwrap()))
            .await;
        map_version_only(result)
    }

    async fn remove_character(
        &self,
        cmd: RemoveCharacter,
    ) -> Result<AggregateVersion, DomainError> {
        let id = cmd.id;
        let version = cmd.version;
        check_nonzero_version(version)?;
        let result = SceneAggregate::execute(&self.cmd_service, id, cmd)
            .expected_version(ExpectedVersion::Exact(domain_to_stream(version).unwrap()))
            .await;
        map_version_only(result)
    }
}

/// Command adapter for the Character aggregate.
#[derive(Clone, Debug)]
pub struct CharacterCommandsImpl {
    cmd_service: CommandService,
}

impl CharacterCommandsImpl {
    pub fn new(cmd_service: CommandService) -> Self {
        Self { cmd_service }
    }
}

impl CharacterCommands for CharacterCommandsImpl {
    async fn create(&self, cmd: CreateCharacter) -> Result<(Uuid, AggregateVersion), DomainError> {
        let id = cmd.id;
        let result = CharacterAggregate::execute(&self.cmd_service, id, cmd)
            .expected_version(ExpectedVersion::Empty)
            .await;
        map_executed(id, result)
    }

    async fn update_measurements(
        &self,
        cmd: UpdateMeasurements,
    ) -> Result<AggregateVersion, DomainError> {
        let id = cmd.id;
        let version = cmd.version;
        check_nonzero_version(version)?;
        let result = CharacterAggregate::execute(&self.cmd_service, id, cmd)
            .expected_version(ExpectedVersion::Exact(domain_to_stream(version).unwrap()))
            .await;
        map_version_only(result)
    }

    async fn update_contact_info(
        &self,
        cmd: UpdateContactInfo,
    ) -> Result<AggregateVersion, DomainError> {
        let id = cmd.id;
        let version = cmd.version;
        check_nonzero_version(version)?;
        let result = CharacterAggregate::execute(&self.cmd_service, id, cmd)
            .expected_version(ExpectedVersion::Exact(domain_to_stream(version).unwrap()))
            .await;
        map_version_only(result)
    }
}

/// Command adapter for the Costume aggregate.
#[derive(Clone, Debug)]
pub struct CostumeCommandsImpl {
    cmd_service: CommandService,
}

impl CostumeCommandsImpl {
    pub fn new(cmd_service: CommandService) -> Self {
        Self { cmd_service }
    }
}

impl CostumeCommands for CostumeCommandsImpl {
    async fn create(&self, cmd: CreateCostume) -> Result<(Uuid, AggregateVersion), DomainError> {
        let id = cmd.id;
        let result = CostumeAggregate::execute(&self.cmd_service, id, cmd)
            .expected_version(ExpectedVersion::Empty)
            .await;
        map_executed(id, result)
    }

    async fn update_notes(&self, cmd: UpdateCostumeNotes) -> Result<AggregateVersion, DomainError> {
        let id = cmd.id;
        let version = cmd.version;
        check_nonzero_version(version)?;
        let result = CostumeAggregate::execute(&self.cmd_service, id, cmd)
            .expected_version(ExpectedVersion::Exact(domain_to_stream(version).unwrap()))
            .await;
        map_version_only(result)
    }

    async fn assign_to_character(
        &self,
        cmd: AssignCostumeToCharacter,
    ) -> Result<AggregateVersion, DomainError> {
        let id = cmd.id;
        let version = cmd.version;
        check_nonzero_version(version)?;
        let result = CostumeAggregate::execute(&self.cmd_service, id, cmd)
            .expected_version(ExpectedVersion::Exact(domain_to_stream(version).unwrap()))
            .await;
        map_version_only(result)
    }

    async fn unassign(&self, cmd: UnassignCostume) -> Result<AggregateVersion, DomainError> {
        let id = cmd.id;
        let version = cmd.version;
        check_nonzero_version(version)?;
        let result = CostumeAggregate::execute(&self.cmd_service, id, cmd)
            .expected_version(ExpectedVersion::Exact(domain_to_stream(version).unwrap()))
            .await;
        map_version_only(result)
    }

    async fn add_detail(&self, cmd: AddDetail) -> Result<AggregateVersion, DomainError> {
        let id = cmd.id;
        let version = cmd.version;
        check_nonzero_version(version)?;
        let result = CostumeAggregate::execute(&self.cmd_service, id, cmd)
            .expected_version(ExpectedVersion::Exact(domain_to_stream(version).unwrap()))
            .await;
        map_version_only(result)
    }

    async fn remove_detail(&self, cmd: RemoveDetail) -> Result<AggregateVersion, DomainError> {
        let id = cmd.id;
        let version = cmd.version;
        check_nonzero_version(version)?;
        let result = CostumeAggregate::execute(&self.cmd_service, id, cmd)
            .expected_version(ExpectedVersion::Exact(domain_to_stream(version).unwrap()))
            .await;
        map_version_only(result)
    }

    async fn link_photo(&self, cmd: LinkPhoto) -> Result<AggregateVersion, DomainError> {
        let id = cmd.id;
        let version = cmd.version;
        check_nonzero_version(version)?;
        let result = CostumeAggregate::execute(&self.cmd_service, id, cmd)
            .expected_version(ExpectedVersion::Exact(domain_to_stream(version).unwrap()))
            .await;
        map_version_only(result)
    }

    async fn unlink_photo(&self, cmd: UnlinkPhoto) -> Result<AggregateVersion, DomainError> {
        let id = cmd.id;
        let version = cmd.version;
        check_nonzero_version(version)?;
        let result = CostumeAggregate::execute(&self.cmd_service, id, cmd)
            .expected_version(ExpectedVersion::Exact(domain_to_stream(version).unwrap()))
            .await;
        map_version_only(result)
    }
}

/// Command adapter for the Calculation aggregate.
#[derive(Clone, Debug)]
pub struct CalculationCommandsImpl {
    cmd_service: CommandService,
}

impl CalculationCommandsImpl {
    pub fn new(cmd_service: CommandService) -> Self {
        Self { cmd_service }
    }
}

impl CalculationCommands for CalculationCommandsImpl {
    async fn create(
        &self,
        cmd: CreateCalculation,
    ) -> Result<(Uuid, AggregateVersion), DomainError> {
        let id = cmd.id;
        let result = CalculationAggregate::execute(&self.cmd_service, id, cmd)
            .expected_version(ExpectedVersion::Empty)
            .await;
        map_executed(id, result)
    }

    async fn update_header(&self, cmd: UpdateHeaderInfo) -> Result<AggregateVersion, DomainError> {
        let id = cmd.id;
        let version = cmd.version;
        check_nonzero_version(version)?;
        let result = CalculationAggregate::execute(&self.cmd_service, id, cmd)
            .expected_version(ExpectedVersion::Exact(domain_to_stream(version).unwrap()))
            .await;
        map_version_only(result)
    }

    async fn add_item(&self, cmd: AddCalculationItem) -> Result<AggregateVersion, DomainError> {
        let id = cmd.id;
        let version = cmd.version;
        check_nonzero_version(version)?;
        let result = CalculationAggregate::execute(&self.cmd_service, id, cmd)
            .expected_version(ExpectedVersion::Exact(domain_to_stream(version).unwrap()))
            .await;
        map_version_only(result)
    }

    async fn update_item(
        &self,
        cmd: UpdateCalculationItem,
    ) -> Result<AggregateVersion, DomainError> {
        let id = cmd.id;
        let version = cmd.version;
        check_nonzero_version(version)?;
        let result = CalculationAggregate::execute(&self.cmd_service, id, cmd)
            .expected_version(ExpectedVersion::Exact(domain_to_stream(version).unwrap()))
            .await;
        map_version_only(result)
    }

    async fn remove_item(
        &self,
        cmd: RemoveCalculationItem,
    ) -> Result<AggregateVersion, DomainError> {
        let id = cmd.id;
        let version = cmd.version;
        check_nonzero_version(version)?;
        let result = CalculationAggregate::execute(&self.cmd_service, id, cmd)
            .expected_version(ExpectedVersion::Exact(domain_to_stream(version).unwrap()))
            .await;
        map_version_only(result)
    }

    async fn mark_item_paid(&self, cmd: MarkItemAsPaid) -> Result<AggregateVersion, DomainError> {
        let id = cmd.id;
        let version = cmd.version;
        check_nonzero_version(version)?;
        let result = CalculationAggregate::execute(&self.cmd_service, id, cmd)
            .expected_version(ExpectedVersion::Exact(domain_to_stream(version).unwrap()))
            .await;
        map_version_only(result)
    }

    async fn mark_item_unpaid(
        &self,
        cmd: MarkItemAsUnpaid,
    ) -> Result<AggregateVersion, DomainError> {
        let id = cmd.id;
        let version = cmd.version;
        check_nonzero_version(version)?;
        let result = CalculationAggregate::execute(&self.cmd_service, id, cmd)
            .expected_version(ExpectedVersion::Exact(domain_to_stream(version).unwrap()))
            .await;
        map_version_only(result)
    }
}

fn map_version_only<Ent, Err>(
    result: Result<ExecuteResult<Ent>, ExecuteError<Err>>,
) -> Result<AggregateVersion, DomainError>
where
    Ent: kameo_es::Entity + kameo_es::Apply + std::fmt::Debug + Send + Sync + 'static,
    Err: Into<DomainError> + std::fmt::Debug + Send + Sync + 'static,
{
    let (id, version) = map_executed_result(Uuid::nil(), result)?;
    let _ = id;
    Ok(version)
}

fn map_executed<Ent, Err>(
    id: Uuid,
    result: Result<ExecuteResult<Ent>, ExecuteError<Err>>,
) -> Result<(Uuid, AggregateVersion), DomainError>
where
    Ent: kameo_es::Entity + kameo_es::Apply + std::fmt::Debug + Send + Sync + 'static,
    Err: Into<DomainError> + std::fmt::Debug + Send + Sync + 'static,
{
    map_executed_result(id, result)
}

/// Translate a SierraDB stream version (0-based) to the canonical domain version (1-based).
/// `domain_version = stream_version + 1`
#[must_use]
pub fn stream_to_domain(stream_version: u64) -> AggregateVersion {
    AggregateVersion(stream_version + 1)
}

/// Translate the canonical domain version (1-based) back to a SierraDB stream version (0-based).
/// Returns `None` for domain version 0 (no events → no stream version).
#[must_use]
pub fn domain_to_stream(domain_version: AggregateVersion) -> Option<u64> {
    if domain_version.0 == 0 {
        None
    } else {
        Some(domain_version.0 - 1)
    }
}

fn map_executed_result<Ent, Err>(
    id: Uuid,
    result: Result<ExecuteResult<Ent>, ExecuteError<Err>>,
) -> Result<(Uuid, AggregateVersion), DomainError>
where
    Ent: kameo_es::Entity + kameo_es::Apply + std::fmt::Debug + Send + Sync + 'static,
    Err: Into<DomainError> + std::fmt::Debug + Send + Sync + 'static,
{
    match result {
        Ok(ExecuteResult::Executed(events)) => {
            let version = events
                .last()
                .map(|e| stream_to_domain(e.stream_version))
                .ok_or_else(|| DomainError::Conflict("command produced no events".into()))?;
            Ok((id, version))
        }
        Ok(ExecuteResult::Idempotent { current_version }) => {
            Ok((id, version_from_current(current_version)))
        }
        Ok(ExecuteResult::PendingTransaction { .. }) => Err(DomainError::Conflict(
            "pending transaction not supported".into(),
        )),
        Err(ExecuteError::Handle(err)) => Err(err.into()),
        Err(ExecuteError::IncorrectExpectedVersion {
            stream_id, current, ..
        }) => Err(DomainError::VersionConflict {
            entity: stream_id.to_string(),
            expected: AggregateVersion(0),
            current: version_from_current(current),
        }),
        Err(err) => Err(DomainError::Conflict(err.to_string())),
    }
}

/// Map `CurrentVersion` to the canonical domain version.
/// `Empty` (no events) → `AggregateVersion(0)` — no domain version yet.
/// `Current(v)` (SierraDB reports version `v`) → `AggregateVersion(v + 1)`.
fn version_from_current(current: CurrentVersion) -> AggregateVersion {
    match current {
        CurrentVersion::Current(v) => stream_to_domain(v),
        CurrentVersion::Empty => AggregateVersion(0),
    }
}

/// Map `ExpectedVersion` to the canonical domain version.
/// Only used in error context to inform the caller what they supplied.
#[expect(dead_code)] // reserved for future error reporting
fn version_from_expected(expected: ExpectedVersion) -> AggregateVersion {
    match expected {
        ExpectedVersion::Exact(v) => AggregateVersion(v),
        ExpectedVersion::Empty => AggregateVersion::INITIAL,
        _ => AggregateVersion::INITIAL,
    }
}

/// Check that a domain version is non-zero (valid for update operations).
/// Returns `DomainError::VersionConflict` when `version.0 == 0`.
fn check_nonzero_version(version: AggregateVersion) -> Result<(), DomainError> {
    if version.0 == 0 {
        Err(DomainError::VersionConflict {
            entity: String::new(),
            expected: AggregateVersion(0),
            current: AggregateVersion(0),
        })
    } else {
        Ok(())
    }
}

#[cfg(test)]
mod translation_tests {
    use super::*;

    #[test]
    fn stream_to_domain_basic() {
        assert_eq!(stream_to_domain(0), AggregateVersion(1));
        assert_eq!(stream_to_domain(1), AggregateVersion(2));
        assert_eq!(stream_to_domain(99), AggregateVersion(100));
    }

    #[test]
    fn domain_to_stream_basic() {
        assert_eq!(domain_to_stream(AggregateVersion(1)), Some(0));
        assert_eq!(domain_to_stream(AggregateVersion(2)), Some(1));
        assert_eq!(domain_to_stream(AggregateVersion(100)), Some(99));
    }

    #[test]
    fn domain_to_stream_zero_returns_none() {
        assert_eq!(domain_to_stream(AggregateVersion(0)), None);
    }

    #[test]
    fn version_from_current_current() {
        assert_eq!(
            version_from_current(CurrentVersion::Current(0)),
            AggregateVersion(1)
        );
        assert_eq!(
            version_from_current(CurrentVersion::Current(5)),
            AggregateVersion(6)
        );
    }

    #[test]
    fn version_from_current_empty() {
        assert_eq!(
            version_from_current(CurrentVersion::Empty),
            AggregateVersion(0)
        );
    }

    #[test]
    fn check_nonzero_version_rejects_zero() {
        let result = check_nonzero_version(AggregateVersion(0));
        assert!(result.is_err());
    }

    #[test]
    fn check_nonzero_version_accepts_initial() {
        let result = check_nonzero_version(AggregateVersion::INITIAL);
        assert!(result.is_ok());
    }

    #[test]
    fn roundtrip_stream_domain() {
        for sv in 0..100 {
            let domain = stream_to_domain(sv);
            assert_eq!(domain_to_stream(domain), Some(sv));
        }
    }
}
