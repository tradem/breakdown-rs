// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors

use std::collections::HashMap;
use std::sync::Arc;

use breakdown_core::block::commands::{CreateBlock, UpdateBlockTimeSpan};
use breakdown_core::block::ports::{BlockCommands, BlockRepository};
use breakdown_core::block::views::BlockView;
use breakdown_core::character::category::CharacterCategory;
use breakdown_core::character::commands::{CreateCharacter, UpdateContactInfo, UpdateMeasurements};
use breakdown_core::character::ports::{CharacterCommands, CharacterRepository};
use breakdown_core::character::views::CharacterView;
use breakdown_core::costume::commands::{
    AddDetail, AssignCostumeToCharacter, CreateCostume, LinkPhoto, RemoveDetail, UnassignCostume,
    UnlinkPhoto, UpdateCostumeNotes,
};
use breakdown_core::costume::ports::{CostumeCommands, CostumeRepository};
use breakdown_core::costume::views::CostumeView;
use breakdown_core::episode::commands::{CreateEpisode, RenameEpisode};
use breakdown_core::episode::ports::{EpisodeCommands, EpisodeRepository};
use breakdown_core::episode::views::EpisodeView;
use breakdown_core::error::DomainError;
use breakdown_core::scene::commands::{
    AssignCharacter, CreateScene, RemoveCharacter, ScheduleSceneOnShootingDay,
    UnscheduleSceneFromShootingDay, UpdateSceneDetails,
};
use breakdown_core::scene::ports::{SceneCommands, SceneRepository};
use breakdown_core::scene::views::SceneView;
use breakdown_core::shooting_day::commands::{
    ArchiveShootingDay, CreateShootingDay, ReorderShootingDay, RenameShootingDay,
    RescheduleShootingDay,
};
use breakdown_core::shooting_day::ports::{ShootingDayCommands, ShootingDayRepository};
use breakdown_core::shooting_day::views::ShootingDayView;
use breakdown_core::season::commands::{CreateSeason, RenameSeason};
use breakdown_core::season::ports::{SeasonCommands, SeasonRepository};
use breakdown_core::season::views::SeasonView;
use breakdown_core::shared::{AggregateVersion, BlockId, EpisodeId, SeasonId, SeriesId, ShootingDayId};
use tokio::sync::Mutex;
use uuid::Uuid;

use async_trait::async_trait;
use breakdown_core::audit::{AuditEntry, AuditRepository};
use breakdown_core::membership::commands::{
    AcceptInvitation, BootstrapOwner, GrantRole, InviteMember, LeaveBlock, RemoveMember,
};
use breakdown_core::membership::ports::{MembershipCommands, MembershipRepository};
use breakdown_core::membership::{MembershipStateKind, MembershipView, Role};
use breakdown_core::shared::UserId;
use chrono::{DateTime, Utc};
use std::collections::HashSet;

use crate::state::Ports;

#[derive(Clone, Default)]
pub(crate) struct FakeSceneCommands;

impl SceneCommands for FakeSceneCommands {
    async fn create(&self, cmd: CreateScene) -> Result<(Uuid, AggregateVersion), DomainError> {
        Ok((cmd.id, AggregateVersion::INITIAL))
    }
    async fn update_details(
        &self,
        _cmd: UpdateSceneDetails,
    ) -> Result<AggregateVersion, DomainError> {
        Ok(AggregateVersion::INITIAL.next())
    }
    async fn assign_character(
        &self,
        _cmd: AssignCharacter,
    ) -> Result<AggregateVersion, DomainError> {
        Ok(AggregateVersion::INITIAL.next())
    }
    async fn remove_character(
        &self,
        _cmd: RemoveCharacter,
    ) -> Result<AggregateVersion, DomainError> {
        Ok(AggregateVersion::INITIAL.next())
    }
    async fn schedule_on_shooting_day(
        &self,
        _cmd: ScheduleSceneOnShootingDay,
    ) -> Result<AggregateVersion, DomainError> {
        Ok(AggregateVersion::INITIAL.next())
    }
    async fn unschedule_from_shooting_day(
        &self,
        _cmd: UnscheduleSceneFromShootingDay,
    ) -> Result<AggregateVersion, DomainError> {
        Ok(AggregateVersion::INITIAL.next())
    }
}

#[derive(Clone, Default)]
pub(crate) struct FakeCharacterCommands;

impl CharacterCommands for FakeCharacterCommands {
    async fn create(&self, cmd: CreateCharacter) -> Result<(Uuid, AggregateVersion), DomainError> {
        Ok((cmd.id, AggregateVersion::INITIAL))
    }
    async fn update_measurements(
        &self,
        _cmd: UpdateMeasurements,
    ) -> Result<AggregateVersion, DomainError> {
        Ok(AggregateVersion::INITIAL.next())
    }
    async fn update_contact_info(
        &self,
        _cmd: UpdateContactInfo,
    ) -> Result<AggregateVersion, DomainError> {
        Ok(AggregateVersion::INITIAL.next())
    }
}

#[derive(Clone, Default)]
pub(crate) struct FakeCostumeCommands;

impl CostumeCommands for FakeCostumeCommands {
    async fn create(&self, cmd: CreateCostume) -> Result<(Uuid, AggregateVersion), DomainError> {
        Ok((cmd.id, AggregateVersion::INITIAL))
    }
    async fn update_notes(
        &self,
        _cmd: UpdateCostumeNotes,
    ) -> Result<AggregateVersion, DomainError> {
        Ok(AggregateVersion::INITIAL.next())
    }
    async fn assign_to_character(
        &self,
        _cmd: AssignCostumeToCharacter,
    ) -> Result<AggregateVersion, DomainError> {
        Ok(AggregateVersion::INITIAL.next())
    }
    async fn unassign(&self, _cmd: UnassignCostume) -> Result<AggregateVersion, DomainError> {
        Ok(AggregateVersion::INITIAL.next())
    }
    async fn add_detail(&self, _cmd: AddDetail) -> Result<AggregateVersion, DomainError> {
        Ok(AggregateVersion::INITIAL.next())
    }
    async fn remove_detail(&self, _cmd: RemoveDetail) -> Result<AggregateVersion, DomainError> {
        Ok(AggregateVersion::INITIAL.next())
    }
    async fn link_photo(&self, _cmd: LinkPhoto) -> Result<AggregateVersion, DomainError> {
        Ok(AggregateVersion::INITIAL.next())
    }
    async fn unlink_photo(&self, _cmd: UnlinkPhoto) -> Result<AggregateVersion, DomainError> {
        Ok(AggregateVersion::INITIAL.next())
    }
}

#[derive(Clone, Default)]
pub(crate) struct FakeSeasonCommands;

impl SeasonCommands for FakeSeasonCommands {
    async fn create(&self, cmd: CreateSeason) -> Result<(Uuid, AggregateVersion), DomainError> {
        Ok((cmd.id, AggregateVersion::INITIAL))
    }
    async fn rename(&self, _cmd: RenameSeason) -> Result<AggregateVersion, DomainError> {
        Ok(AggregateVersion::INITIAL.next())
    }
}

#[derive(Clone, Default)]
pub(crate) struct FakeBlockCommands;

impl BlockCommands for FakeBlockCommands {
    async fn create(&self, cmd: CreateBlock) -> Result<(Uuid, AggregateVersion), DomainError> {
        Ok((cmd.id, AggregateVersion::INITIAL))
    }
    async fn update_time_span(
        &self,
        _cmd: UpdateBlockTimeSpan,
    ) -> Result<AggregateVersion, DomainError> {
        Ok(AggregateVersion::INITIAL.next())
    }
}

#[derive(Clone, Default)]
pub(crate) struct FakeEpisodeCommands;

impl EpisodeCommands for FakeEpisodeCommands {
    async fn create(&self, cmd: CreateEpisode) -> Result<(Uuid, AggregateVersion), DomainError> {
        Ok((cmd.id, AggregateVersion::INITIAL))
    }
    async fn rename(&self, _cmd: RenameEpisode) -> Result<AggregateVersion, DomainError> {
        Ok(AggregateVersion::INITIAL.next())
    }
}

// ---- Membership fakes (Section 6.4) ----

/// In-memory membership command adapter that records the last dispatched
/// command per method so handler tests can assert actor/target mapping.
#[derive(Clone, Default)]
pub(crate) struct FakeMembershipCommands {
    pub(crate) last_invite: Arc<Mutex<Option<(UserId, InviteMember)>>>,
    pub(crate) last_accept: Arc<Mutex<Option<(UserId, AcceptInvitation)>>>,
    pub(crate) last_grant: Arc<Mutex<Option<(UserId, GrantRole)>>>,
    pub(crate) last_remove: Arc<Mutex<Option<(UserId, RemoveMember)>>>,
    pub(crate) last_leave: Arc<Mutex<Option<(UserId, LeaveBlock)>>>,
    pub(crate) last_bootstrap: Arc<Mutex<Option<(UserId, BootstrapOwner)>>>,
}

#[async_trait]
impl MembershipCommands for FakeMembershipCommands {
    async fn invite(&self, actor: UserId, cmd: InviteMember) -> Result<(), DomainError> {
        *self.last_invite.lock().await = Some((actor, cmd));
        Ok(())
    }
    async fn accept_invitation(
        &self,
        actor: UserId,
        cmd: AcceptInvitation,
    ) -> Result<(), DomainError> {
        *self.last_accept.lock().await = Some((actor, cmd));
        Ok(())
    }
    async fn grant_role(&self, actor: UserId, cmd: GrantRole) -> Result<(), DomainError> {
        *self.last_grant.lock().await = Some((actor, cmd));
        Ok(())
    }
    async fn remove_member(&self, actor: UserId, cmd: RemoveMember) -> Result<(), DomainError> {
        *self.last_remove.lock().await = Some((actor, cmd));
        Ok(())
    }
    async fn leave_block(&self, actor: UserId, cmd: LeaveBlock) -> Result<(), DomainError> {
        *self.last_leave.lock().await = Some((actor, cmd));
        Ok(())
    }
    async fn bootstrap_owner(&self, actor: UserId, cmd: BootstrapOwner) -> Result<(), DomainError> {
        *self.last_bootstrap.lock().await = Some((actor, cmd));
        Ok(())
    }
}

/// In-memory membership repository whose active-membership is driven by a
/// controllable set of `(block_id, user_id)` pairs.
#[derive(Clone, Default)]
pub(crate) struct FakeMembershipRepo {
    pub(crate) members: Arc<Mutex<HashSet<(BlockId, UserId)>>>,
}

#[async_trait]
impl MembershipRepository for FakeMembershipRepo {
    async fn find(
        &self,
        block_id: BlockId,
        user_id: UserId,
    ) -> Result<Option<MembershipView>, DomainError> {
        if self
            .members
            .lock()
            .await
            .contains(&(block_id, user_id.clone()))
        {
            Ok(Some(MembershipView {
                block_id,
                user_id,
                role: Role::CostumeAssistant,
                state: MembershipStateKind::Active,
                joined_at: Utc::now(),
            }))
        } else {
            Ok(None)
        }
    }
    async fn list_by_block(
        &self,
        block_id: BlockId,
        _limit: i64,
        _offset: i64,
    ) -> Result<Vec<MembershipView>, DomainError> {
        let members = self.members.lock().await;
        Ok(members
            .iter()
            .filter(|(b, _)| *b == block_id)
            .map(|(b, u)| MembershipView {
                block_id: *b,
                user_id: u.clone(),
                role: Role::CostumeAssistant,
                state: MembershipStateKind::Active,
                joined_at: Utc::now(),
            })
            .collect())
    }
    async fn is_active_member(
        &self,
        block_id: BlockId,
        user_id: UserId,
    ) -> Result<bool, DomainError> {
        Ok(self.members.lock().await.contains(&(block_id, user_id)))
    }
}

#[derive(Clone)]
pub(crate) struct FakeSceneRepo {
    pub(crate) scenes: Arc<Mutex<HashMap<Uuid, SceneView>>>,
}

impl Default for FakeSceneRepo {
    fn default() -> Self {
        Self {
            scenes: Arc::new(Mutex::new(HashMap::new())),
        }
    }
}

impl SceneRepository for FakeSceneRepo {
    async fn find_by_id(&self, id: Uuid) -> Result<SceneView, DomainError> {
        self.scenes
            .lock()
            .await
            .get(&id)
            .cloned()
            .ok_or_else(|| DomainError::NotFound(format!("Scene({id})")))
    }
    async fn list_by_episode(
        &self,
        _episode_id: EpisodeId,
        _limit: i64,
        _offset: i64,
    ) -> Result<Vec<SceneView>, DomainError> {
        Ok(Vec::new())
    }
    async fn scenes_by_character(
        &self,
        _character_id: Uuid,
    ) -> Result<Vec<SceneView>, DomainError> {
        Ok(Vec::new())
    }
}

#[derive(Clone, Default)]
pub(crate) struct FakeCharacterRepo;

impl CharacterRepository for FakeCharacterRepo {
    async fn find_by_id(&self, id: Uuid) -> Result<CharacterView, DomainError> {
        Err(DomainError::NotFound(format!("Character({id})")))
    }
    async fn list_by_season(
        &self,
        _season_id: SeasonId,
        _limit: i64,
        _offset: i64,
    ) -> Result<Vec<CharacterView>, DomainError> {
        Ok(Vec::new())
    }
    async fn list_by_season_and_category(
        &self,
        _season_id: SeasonId,
        _category: CharacterCategory,
        _limit: i64,
        _offset: i64,
    ) -> Result<Vec<CharacterView>, DomainError> {
        Ok(Vec::new())
    }
    async fn appearances(&self, _character_id: Uuid) -> Result<Vec<EpisodeId>, DomainError> {
        Ok(Vec::new())
    }
}

#[derive(Clone, Default)]
pub(crate) struct FakeCostumeRepo;

impl CostumeRepository for FakeCostumeRepo {
    async fn find_by_id(&self, id: Uuid) -> Result<CostumeView, DomainError> {
        Err(DomainError::NotFound(format!("Costume({id})")))
    }
    async fn list_by_season(
        &self,
        _season_id: SeasonId,
        _limit: i64,
        _offset: i64,
    ) -> Result<Vec<CostumeView>, DomainError> {
        Ok(Vec::new())
    }
    async fn costumes_by_character(
        &self,
        _character_id: Uuid,
    ) -> Result<Vec<CostumeView>, DomainError> {
        Ok(Vec::new())
    }
    async fn costume_with_details_photos(&self, id: Uuid) -> Result<CostumeView, DomainError> {
        Err(DomainError::NotFound(format!("Costume({id})")))
    }
}

#[derive(Clone, Default)]
pub(crate) struct FakeSeasonRepo;

impl SeasonRepository for FakeSeasonRepo {
    async fn find_by_id(&self, id: Uuid) -> Result<SeasonView, DomainError> {
        Err(DomainError::NotFound(format!("Season({id})")))
    }
    async fn list_by_series(
        &self,
        _series_id: SeriesId,
        _limit: i64,
        _offset: i64,
    ) -> Result<Vec<SeasonView>, DomainError> {
        Ok(Vec::new())
    }
    async fn find_by_series_and_number(
        &self,
        _series_id: SeriesId,
        _number: i32,
    ) -> Result<Option<SeasonView>, DomainError> {
        Ok(None)
    }
}

#[derive(Clone, Default)]
pub(crate) struct FakeBlockRepo;

impl BlockRepository for FakeBlockRepo {
    async fn find_by_id(&self, id: Uuid) -> Result<BlockView, DomainError> {
        Err(DomainError::NotFound(format!("Block({id})")))
    }
    async fn list_by_season(
        &self,
        _season_id: SeasonId,
        _limit: i64,
        _offset: i64,
    ) -> Result<Vec<BlockView>, DomainError> {
        Ok(Vec::new())
    }
    async fn find_by_series_and_number(
        &self,
        _series_id: SeriesId,
        _number: i32,
    ) -> Result<Option<BlockView>, DomainError> {
        Ok(None)
    }
}

#[derive(Clone, Default)]
pub(crate) struct FakeEpisodeRepo;

impl EpisodeRepository for FakeEpisodeRepo {
    async fn find_by_id(&self, id: Uuid) -> Result<EpisodeView, DomainError> {
        Err(DomainError::NotFound(format!("Episode({id})")))
    }
    async fn list_by_block(
        &self,
        _block_id: BlockId,
        _limit: i64,
        _offset: i64,
    ) -> Result<Vec<EpisodeView>, DomainError> {
        Ok(Vec::new())
    }
    async fn list_by_series(
        &self,
        _series_id: SeriesId,
        _limit: i64,
        _offset: i64,
    ) -> Result<Vec<EpisodeView>, DomainError> {
        Ok(Vec::new())
    }
    async fn find_by_series_and_number(
        &self,
        _series_id: SeriesId,
        _number: i32,
    ) -> Result<Option<EpisodeView>, DomainError> {
        Ok(None)
    }
}

#[derive(Clone, Default)]
pub(crate) struct FakeAuditRepo {
    pub(crate) entries: Arc<Mutex<Vec<AuditEntry>>>,
}

#[async_trait]
impl AuditRepository for FakeAuditRepo {
    async fn list_by_block(
        &self,
        block_id: BlockId,
        limit: i64,
        offset: i64,
    ) -> Result<Vec<AuditEntry>, DomainError> {
        let all = self.entries.lock().await;
        Ok(all
            .iter()
            .filter(|e| e.block_id == Some(block_id))
            .skip(offset as usize)
            .take(limit as usize)
            .cloned()
            .collect())
    }
    async fn list_by_actor(
        &self,
        _actor: UserId,
        _limit: i64,
        _offset: i64,
    ) -> Result<Vec<AuditEntry>, DomainError> {
        Ok(Vec::new())
    }
    async fn list_by_time_range(
        &self,
        _from: DateTime<Utc>,
        _to: DateTime<Utc>,
        _limit: i64,
        _offset: i64,
    ) -> Result<Vec<AuditEntry>, DomainError> {
        Ok(Vec::new())
    }
    async fn list_by_entity(
        &self,
        _entity_type: &str,
        _entity_id: &str,
        _limit: i64,
        _offset: i64,
    ) -> Result<Vec<AuditEntry>, DomainError> {
        Ok(Vec::new())
    }
}

#[derive(Clone, Default)]
pub(crate) struct FakeShootingDayCommands;

impl ShootingDayCommands for FakeShootingDayCommands {
    async fn create(
        &self,
        cmd: CreateShootingDay,
    ) -> Result<(ShootingDayId, AggregateVersion), DomainError> {
        Ok((cmd.id, AggregateVersion::INITIAL))
    }
    async fn rename(&self, _cmd: RenameShootingDay) -> Result<AggregateVersion, DomainError> {
        Ok(AggregateVersion::INITIAL.next())
    }
    async fn reschedule(
        &self,
        _cmd: RescheduleShootingDay,
    ) -> Result<AggregateVersion, DomainError> {
        Ok(AggregateVersion::INITIAL.next())
    }
    async fn reorder(&self, _cmd: ReorderShootingDay) -> Result<AggregateVersion, DomainError> {
        Ok(AggregateVersion::INITIAL.next())
    }
    async fn archive(&self, _cmd: ArchiveShootingDay) -> Result<AggregateVersion, DomainError> {
        Ok(AggregateVersion::INITIAL.next())
    }
}

#[derive(Clone, Default)]
pub(crate) struct FakeShootingDayRepo;

impl ShootingDayRepository for FakeShootingDayRepo {
    async fn find_by_id(&self, id: ShootingDayId) -> Result<ShootingDayView, DomainError> {
        Err(DomainError::NotFound(format!("ShootingDay({id})")))
    }
    async fn list_by_episode(
        &self,
        _episode_id: EpisodeId,
    ) -> Result<Vec<ShootingDayView>, DomainError> {
        Ok(Vec::new())
    }
    async fn scenes_by_shooting_day(
        &self,
        _shooting_day_id: ShootingDayId,
    ) -> Result<Vec<SceneView>, DomainError> {
        Ok(Vec::new())
    }
}

#[derive(Clone, Default)]
pub(crate) struct FakePorts {
    pub(crate) scene_commands: FakeSceneCommands,
    pub(crate) scene_repo: FakeSceneRepo,
    pub(crate) character_commands: FakeCharacterCommands,
    pub(crate) character_repo: FakeCharacterRepo,
    pub(crate) costume_commands: FakeCostumeCommands,
    pub(crate) costume_repo: FakeCostumeRepo,
    pub(crate) season_commands: FakeSeasonCommands,
    pub(crate) season_repo: FakeSeasonRepo,
    pub(crate) block_commands: FakeBlockCommands,
    pub(crate) block_repo: FakeBlockRepo,
    pub(crate) episode_commands: FakeEpisodeCommands,
    pub(crate) episode_repo: FakeEpisodeRepo,
    pub(crate) membership_commands: FakeMembershipCommands,
    pub(crate) membership_repo: FakeMembershipRepo,
    pub(crate) audit_repo: FakeAuditRepo,
    pub(crate) shooting_day_commands: FakeShootingDayCommands,
    pub(crate) shooting_day_repo: FakeShootingDayRepo,
}

impl Ports for FakePorts {
    type SceneCommands = FakeSceneCommands;
    type SceneRepo = FakeSceneRepo;
    type CharacterCommands = FakeCharacterCommands;
    type CharacterRepo = FakeCharacterRepo;
    type CostumeCommands = FakeCostumeCommands;
    type CostumeRepo = FakeCostumeRepo;
    type SeasonCommands = FakeSeasonCommands;
    type SeasonRepo = FakeSeasonRepo;
    type BlockCommands = FakeBlockCommands;
    type BlockRepo = FakeBlockRepo;
    type EpisodeCommands = FakeEpisodeCommands;
    type EpisodeRepo = FakeEpisodeRepo;
    type MembershipCommands = FakeMembershipCommands;
    type MembershipRepo = FakeMembershipRepo;
    type AuditRepo = FakeAuditRepo;
    type ShootingDayCommands = FakeShootingDayCommands;
    type ShootingDayRepo = FakeShootingDayRepo;

    fn scene_commands(&self) -> &Self::SceneCommands {
        &self.scene_commands
    }
    fn scene_repo(&self) -> &Self::SceneRepo {
        &self.scene_repo
    }
    fn character_commands(&self) -> &Self::CharacterCommands {
        &self.character_commands
    }
    fn character_repo(&self) -> &Self::CharacterRepo {
        &self.character_repo
    }
    fn costume_commands(&self) -> &Self::CostumeCommands {
        &self.costume_commands
    }
    fn costume_repo(&self) -> &Self::CostumeRepo {
        &self.costume_repo
    }
    fn season_commands(&self) -> &Self::SeasonCommands {
        &self.season_commands
    }
    fn season_repo(&self) -> &Self::SeasonRepo {
        &self.season_repo
    }
    fn block_commands(&self) -> &Self::BlockCommands {
        &self.block_commands
    }
    fn block_repo(&self) -> &Self::BlockRepo {
        &self.block_repo
    }
    fn episode_commands(&self) -> &Self::EpisodeCommands {
        &self.episode_commands
    }
    fn episode_repo(&self) -> &Self::EpisodeRepo {
        &self.episode_repo
    }
    fn membership_commands(&self) -> &Self::MembershipCommands {
        &self.membership_commands
    }
    fn membership_repo(&self) -> &Self::MembershipRepo {
        &self.membership_repo
    }
    fn audit_repo(&self) -> &Self::AuditRepo {
        &self.audit_repo
    }
    fn shooting_day_commands(&self) -> &Self::ShootingDayCommands {
        &self.shooting_day_commands
    }
    fn shooting_day_repo(&self) -> &Self::ShootingDayRepo {
        &self.shooting_day_repo
    }
}
