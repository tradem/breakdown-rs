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
        let result = SceneAggregate::execute(&self.cmd_service, id, cmd)
            .expected_version(ExpectedVersion::Exact(version.0))
            .await;
        map_version_only(result)
    }

    async fn assign_character(
        &self,
        cmd: AssignCharacter,
    ) -> Result<AggregateVersion, DomainError> {
        let id = cmd.id;
        let version = cmd.version;
        let result = SceneAggregate::execute(&self.cmd_service, id, cmd)
            .expected_version(ExpectedVersion::Exact(version.0))
            .await;
        map_version_only(result)
    }

    async fn remove_character(
        &self,
        cmd: RemoveCharacter,
    ) -> Result<AggregateVersion, DomainError> {
        let id = cmd.id;
        let version = cmd.version;
        let result = SceneAggregate::execute(&self.cmd_service, id, cmd)
            .expected_version(ExpectedVersion::Exact(version.0))
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
        let result = CharacterAggregate::execute(&self.cmd_service, id, cmd)
            .expected_version(ExpectedVersion::Exact(version.0))
            .await;
        map_version_only(result)
    }

    async fn update_contact_info(
        &self,
        cmd: UpdateContactInfo,
    ) -> Result<AggregateVersion, DomainError> {
        let id = cmd.id;
        let version = cmd.version;
        let result = CharacterAggregate::execute(&self.cmd_service, id, cmd)
            .expected_version(ExpectedVersion::Exact(version.0))
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
        let result = CostumeAggregate::execute(&self.cmd_service, id, cmd)
            .expected_version(ExpectedVersion::Exact(version.0))
            .await;
        map_version_only(result)
    }

    async fn assign_to_character(
        &self,
        cmd: AssignCostumeToCharacter,
    ) -> Result<AggregateVersion, DomainError> {
        let id = cmd.id;
        let version = cmd.version;
        let result = CostumeAggregate::execute(&self.cmd_service, id, cmd)
            .expected_version(ExpectedVersion::Exact(version.0))
            .await;
        map_version_only(result)
    }

    async fn unassign(&self, cmd: UnassignCostume) -> Result<AggregateVersion, DomainError> {
        let id = cmd.id;
        let version = cmd.version;
        let result = CostumeAggregate::execute(&self.cmd_service, id, cmd)
            .expected_version(ExpectedVersion::Exact(version.0))
            .await;
        map_version_only(result)
    }

    async fn add_detail(&self, cmd: AddDetail) -> Result<AggregateVersion, DomainError> {
        let id = cmd.id;
        let version = cmd.version;
        let result = CostumeAggregate::execute(&self.cmd_service, id, cmd)
            .expected_version(ExpectedVersion::Exact(version.0))
            .await;
        map_version_only(result)
    }

    async fn remove_detail(&self, cmd: RemoveDetail) -> Result<AggregateVersion, DomainError> {
        let id = cmd.id;
        let version = cmd.version;
        let result = CostumeAggregate::execute(&self.cmd_service, id, cmd)
            .expected_version(ExpectedVersion::Exact(version.0))
            .await;
        map_version_only(result)
    }

    async fn link_photo(&self, cmd: LinkPhoto) -> Result<AggregateVersion, DomainError> {
        let id = cmd.id;
        let version = cmd.version;
        let result = CostumeAggregate::execute(&self.cmd_service, id, cmd)
            .expected_version(ExpectedVersion::Exact(version.0))
            .await;
        map_version_only(result)
    }

    async fn unlink_photo(&self, cmd: UnlinkPhoto) -> Result<AggregateVersion, DomainError> {
        let id = cmd.id;
        let version = cmd.version;
        let result = CostumeAggregate::execute(&self.cmd_service, id, cmd)
            .expected_version(ExpectedVersion::Exact(version.0))
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
        let result = CalculationAggregate::execute(&self.cmd_service, id, cmd)
            .expected_version(ExpectedVersion::Exact(version.0))
            .await;
        map_version_only(result)
    }

    async fn add_item(&self, cmd: AddCalculationItem) -> Result<AggregateVersion, DomainError> {
        let id = cmd.id;
        let version = cmd.version;
        let result = CalculationAggregate::execute(&self.cmd_service, id, cmd)
            .expected_version(ExpectedVersion::Exact(version.0))
            .await;
        map_version_only(result)
    }

    async fn update_item(
        &self,
        cmd: UpdateCalculationItem,
    ) -> Result<AggregateVersion, DomainError> {
        let id = cmd.id;
        let version = cmd.version;
        let result = CalculationAggregate::execute(&self.cmd_service, id, cmd)
            .expected_version(ExpectedVersion::Exact(version.0))
            .await;
        map_version_only(result)
    }

    async fn remove_item(
        &self,
        cmd: RemoveCalculationItem,
    ) -> Result<AggregateVersion, DomainError> {
        let id = cmd.id;
        let version = cmd.version;
        let result = CalculationAggregate::execute(&self.cmd_service, id, cmd)
            .expected_version(ExpectedVersion::Exact(version.0))
            .await;
        map_version_only(result)
    }

    async fn mark_item_paid(&self, cmd: MarkItemAsPaid) -> Result<AggregateVersion, DomainError> {
        let id = cmd.id;
        let version = cmd.version;
        let result = CalculationAggregate::execute(&self.cmd_service, id, cmd)
            .expected_version(ExpectedVersion::Exact(version.0))
            .await;
        map_version_only(result)
    }

    async fn mark_item_unpaid(
        &self,
        cmd: MarkItemAsUnpaid,
    ) -> Result<AggregateVersion, DomainError> {
        let id = cmd.id;
        let version = cmd.version;
        let result = CalculationAggregate::execute(&self.cmd_service, id, cmd)
            .expected_version(ExpectedVersion::Exact(version.0))
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
                .map(|e| AggregateVersion(e.stream_version))
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
            stream_id,
            current,
            expected,
            ..
        }) => Err(DomainError::VersionConflict {
            entity: stream_id.to_string(),
            expected: version_from_expected(expected),
            current: version_from_current(current),
        }),
        Err(err) => Err(DomainError::Conflict(err.to_string())),
    }
}

fn version_from_current(current: CurrentVersion) -> AggregateVersion {
    match current {
        CurrentVersion::Current(v) => AggregateVersion(v),
        CurrentVersion::Empty => AggregateVersion::INITIAL,
    }
}

fn version_from_expected(expected: ExpectedVersion) -> AggregateVersion {
    match expected {
        ExpectedVersion::Exact(v) => AggregateVersion(v),
        ExpectedVersion::Empty => AggregateVersion::INITIAL,
        _ => AggregateVersion::INITIAL,
    }
}
