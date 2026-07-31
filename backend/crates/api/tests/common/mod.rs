// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.2 (neuralwatt)

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
use breakdown_core::costume_category::commands::{
    ArchiveCostumeCategory, CreateCostumeCategory, RenameCostumeCategory, ReorderCostumeCategory,
};
use breakdown_core::costume_category::ports::{CostumeCategoryCommands, CostumeCategoryRepository};
use breakdown_core::costume_category::views::CostumeCategoryView;
use breakdown_core::episode::commands::{CreateEpisode, RenameEpisode};
use breakdown_core::episode::ports::{EpisodeCommands, EpisodeRepository};
use breakdown_core::episode::views::EpisodeView;
use breakdown_core::error::DomainError;
use breakdown_core::photo::commands::{
    DeletePhoto, GenerateVariant, MarkVariantFailed, NormalizeOriginal, UploadPhoto,
};
use breakdown_core::photo::ports::{PhotoCommands, PhotoRepository, PhotoStorage};
use breakdown_core::photo::views::{PhotoBytes, PhotoView};
use breakdown_core::reporting::{
    EnqueueArchivalRequest, EnqueueArchivalResult, ReportArchivalError, ReportArchivalQueue,
    ReportJobId, ReportJobStatus,
};
use breakdown_core::scene::commands::{
    AssignCharacter, CreateScene, RemoveCharacter, ScheduleSceneOnShootingDay,
    UnscheduleSceneFromShootingDay, UpdateSceneDetails,
};
use breakdown_core::scene::ports::{SceneCommands, SceneRepository};
use breakdown_core::scene::views::SceneView;
use breakdown_core::scene_shoot::commands::{
    AddSceneShootNote, FinishSceneShoot, LinkContinuityPhoto, PlanSceneShoot, RemoveSceneShootNote,
    ReplanSceneShoot, SetActualOrder, SkipSceneShoot, StartSceneShoot, UnlinkContinuityPhoto,
    UpdateSceneShootNote,
};
use breakdown_core::scene_shoot::ports::{
    SceneShootCommands, SceneShootReportRepository, SceneShootRepository,
};
use breakdown_core::scene_shoot::views::{DispoRow, SceneShootView, ShootDayRow, SollIstReport};
use breakdown_core::season::commands::{CreateSeason, RenameSeason};
use breakdown_core::season::ports::{SeasonCommands, SeasonRepository};
use breakdown_core::season::views::SeasonView;
use breakdown_core::shared::{
    AggregateVersion, BlockId, EpisodeId, PhotoId, PhotoVariant, SceneShootId, SeasonId, SeriesId,
    ShootingDayId,
};
use breakdown_core::shooting_day::commands::WrapShootingDay;
use breakdown_core::shooting_day::commands::{
    ArchiveShootingDay, CreateShootingDay, RenameShootingDay, ReorderShootingDay,
    RescheduleShootingDay,
};
use breakdown_core::shooting_day::ports::{ShootingDayCommands, ShootingDayRepository};
use breakdown_core::shooting_day::views::ShootingDayView;
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

use api::state::Ports;

#[derive(Clone, Default)]
#[allow(dead_code)]
pub struct FakeSceneCommands;

impl SceneCommands for FakeSceneCommands {
    async fn create(
        &self,
        _actor: UserId,
        cmd: CreateScene,
    ) -> Result<(Uuid, AggregateVersion), DomainError> {
        Ok((cmd.id, AggregateVersion::INITIAL))
    }
    async fn update_details(
        &self,
        _actor: UserId,
        _cmd: UpdateSceneDetails,
    ) -> Result<AggregateVersion, DomainError> {
        Ok(AggregateVersion::INITIAL.next())
    }
    async fn assign_character(
        &self,
        _actor: UserId,
        _cmd: AssignCharacter,
    ) -> Result<AggregateVersion, DomainError> {
        Ok(AggregateVersion::INITIAL.next())
    }
    async fn remove_character(
        &self,
        _actor: UserId,
        _cmd: RemoveCharacter,
    ) -> Result<AggregateVersion, DomainError> {
        Ok(AggregateVersion::INITIAL.next())
    }
    async fn schedule_on_shooting_day(
        &self,
        _actor: UserId,
        _cmd: ScheduleSceneOnShootingDay,
    ) -> Result<AggregateVersion, DomainError> {
        Ok(AggregateVersion::INITIAL.next())
    }
    async fn unschedule_from_shooting_day(
        &self,
        _actor: UserId,
        _cmd: UnscheduleSceneFromShootingDay,
    ) -> Result<AggregateVersion, DomainError> {
        Ok(AggregateVersion::INITIAL.next())
    }
}

#[derive(Clone, Default)]
#[allow(dead_code)]
pub struct FakeCharacterCommands;

impl CharacterCommands for FakeCharacterCommands {
    async fn create(
        &self,
        _actor: UserId,
        cmd: CreateCharacter,
    ) -> Result<(Uuid, AggregateVersion), DomainError> {
        Ok((cmd.id, AggregateVersion::INITIAL))
    }
    async fn update_measurements(
        &self,
        _actor: UserId,
        _cmd: UpdateMeasurements,
    ) -> Result<AggregateVersion, DomainError> {
        Ok(AggregateVersion::INITIAL.next())
    }
    async fn update_contact_info(
        &self,
        _actor: UserId,
        _cmd: UpdateContactInfo,
    ) -> Result<AggregateVersion, DomainError> {
        Ok(AggregateVersion::INITIAL.next())
    }
}

#[derive(Clone, Default)]
#[allow(dead_code)]
pub struct FakeCostumeCommands;

impl CostumeCommands for FakeCostumeCommands {
    async fn create(
        &self,
        _actor: UserId,
        cmd: CreateCostume,
    ) -> Result<(Uuid, AggregateVersion), DomainError> {
        Ok((cmd.id, AggregateVersion::INITIAL))
    }
    async fn update_notes(
        &self,
        _actor: UserId,
        _cmd: UpdateCostumeNotes,
    ) -> Result<AggregateVersion, DomainError> {
        Ok(AggregateVersion::INITIAL.next())
    }
    async fn assign_to_character(
        &self,
        _actor: UserId,
        _cmd: AssignCostumeToCharacter,
    ) -> Result<AggregateVersion, DomainError> {
        Ok(AggregateVersion::INITIAL.next())
    }
    async fn unassign(
        &self,
        _actor: UserId,
        _cmd: UnassignCostume,
    ) -> Result<AggregateVersion, DomainError> {
        Ok(AggregateVersion::INITIAL.next())
    }
    async fn add_detail(
        &self,
        _actor: UserId,
        _cmd: AddDetail,
    ) -> Result<AggregateVersion, DomainError> {
        Ok(AggregateVersion::INITIAL.next())
    }
    async fn remove_detail(
        &self,
        _actor: UserId,
        _cmd: RemoveDetail,
    ) -> Result<AggregateVersion, DomainError> {
        Ok(AggregateVersion::INITIAL.next())
    }
    async fn link_photo(
        &self,
        _actor: UserId,
        _cmd: LinkPhoto,
    ) -> Result<AggregateVersion, DomainError> {
        Ok(AggregateVersion::INITIAL.next())
    }
    async fn unlink_photo(
        &self,
        _actor: UserId,
        _cmd: UnlinkPhoto,
    ) -> Result<AggregateVersion, DomainError> {
        Ok(AggregateVersion::INITIAL.next())
    }
}

#[derive(Clone, Default)]
#[allow(dead_code)]
pub struct FakeCostumeCategoryCommands;

impl CostumeCategoryCommands for FakeCostumeCategoryCommands {
    async fn create(
        &self,
        _actor: UserId,
        cmd: CreateCostumeCategory,
    ) -> Result<(Uuid, AggregateVersion), DomainError> {
        Ok((cmd.id, AggregateVersion::INITIAL))
    }
    async fn rename(
        &self,
        _actor: UserId,
        _cmd: RenameCostumeCategory,
    ) -> Result<AggregateVersion, DomainError> {
        Ok(AggregateVersion::INITIAL.next())
    }
    async fn reorder(
        &self,
        _actor: UserId,
        _cmd: ReorderCostumeCategory,
    ) -> Result<AggregateVersion, DomainError> {
        Ok(AggregateVersion::INITIAL.next())
    }
    async fn archive(
        &self,
        _actor: UserId,
        _cmd: ArchiveCostumeCategory,
    ) -> Result<AggregateVersion, DomainError> {
        Ok(AggregateVersion::INITIAL.next())
    }
}

#[derive(Clone, Default)]
#[allow(dead_code)]
pub struct FakeSeasonCommands;

impl SeasonCommands for FakeSeasonCommands {
    async fn create(
        &self,
        _actor: UserId,
        cmd: CreateSeason,
    ) -> Result<(Uuid, AggregateVersion), DomainError> {
        Ok((cmd.id, AggregateVersion::INITIAL))
    }
    async fn rename(
        &self,
        _actor: UserId,
        _cmd: RenameSeason,
    ) -> Result<AggregateVersion, DomainError> {
        Ok(AggregateVersion::INITIAL.next())
    }
}

#[derive(Clone, Default)]
#[allow(dead_code)]
pub struct FakeBlockCommands;

impl BlockCommands for FakeBlockCommands {
    async fn create(
        &self,
        _actor: UserId,
        cmd: CreateBlock,
    ) -> Result<(Uuid, AggregateVersion), DomainError> {
        Ok((cmd.id, AggregateVersion::INITIAL))
    }
    async fn update_time_span(
        &self,
        _actor: UserId,
        _cmd: UpdateBlockTimeSpan,
    ) -> Result<AggregateVersion, DomainError> {
        Ok(AggregateVersion::INITIAL.next())
    }
}

#[derive(Clone, Default)]
#[allow(dead_code)]
pub struct FakeEpisodeCommands;

impl EpisodeCommands for FakeEpisodeCommands {
    async fn create(
        &self,
        _actor: UserId,
        cmd: CreateEpisode,
    ) -> Result<(Uuid, AggregateVersion), DomainError> {
        Ok((cmd.id, AggregateVersion::INITIAL))
    }
    async fn rename(
        &self,
        _actor: UserId,
        _cmd: RenameEpisode,
    ) -> Result<AggregateVersion, DomainError> {
        Ok(AggregateVersion::INITIAL.next())
    }
}

// ---- Membership fakes (Section 6.4) ----

/// In-memory membership command adapter that records the last dispatched
/// command per method so handler tests can assert actor/target mapping.
#[derive(Clone, Default)]
#[allow(dead_code)]
pub struct FakeMembershipCommands {
    pub last_invite: Arc<Mutex<Option<(UserId, InviteMember)>>>,
    pub last_accept: Arc<Mutex<Option<(UserId, AcceptInvitation)>>>,
    pub last_grant: Arc<Mutex<Option<(UserId, GrantRole)>>>,
    pub last_remove: Arc<Mutex<Option<(UserId, RemoveMember)>>>,
    pub last_leave: Arc<Mutex<Option<(UserId, LeaveBlock)>>>,
    pub last_bootstrap: Arc<Mutex<Option<(UserId, BootstrapOwner)>>>,
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
#[allow(dead_code)]
pub struct FakeMembershipRepo {
    pub members: Arc<Mutex<HashSet<(BlockId, UserId)>>>,
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

    async fn has_active_costume_role_in_season(
        &self,
        season_id: SeasonId,
        user_id: UserId,
    ) -> Result<bool, DomainError> {
        // For test purposes: authorise any user for any season.
        let _ = (season_id, user_id);
        Ok(true)
    }

    async fn has_active_report_archive_role_in_season(
        &self,
        season_id: SeasonId,
        user_id: UserId,
    ) -> Result<bool, DomainError> {
        // Default test fake admits archive roles (designer/supervisor).
        let _ = (season_id, user_id);
        Ok(true)
    }
}

#[derive(Clone)]
#[allow(dead_code)]
pub struct FakeSceneRepo {
    pub scenes: Arc<Mutex<HashMap<Uuid, SceneView>>>,
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
#[allow(dead_code)]
pub struct FakeCharacterRepo;

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
#[allow(dead_code)]
pub struct FakeCostumeRepo;

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
#[allow(dead_code)]
pub struct FakeCostumeCategoryRepo;

impl CostumeCategoryRepository for FakeCostumeCategoryRepo {
    async fn list_by_season(
        &self,
        _season_id: SeasonId,
    ) -> Result<Vec<CostumeCategoryView>, DomainError> {
        Ok(Vec::new())
    }
    async fn count_for_season(&self, _season_id: SeasonId) -> Result<i64, DomainError> {
        Ok(0)
    }
    async fn find_by_id(&self, id: Uuid) -> Result<CostumeCategoryView, DomainError> {
        Err(DomainError::NotFound(format!("CostumeCategory({id})")))
    }
}

#[derive(Clone, Default)]
#[allow(dead_code)]
pub struct FakeSeasonRepo;

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
#[allow(dead_code)]
pub struct FakeBlockRepo;

impl BlockRepository for FakeBlockRepo {
    async fn find_by_id(&self, id: Uuid) -> Result<BlockView, DomainError> {
        // Return a stub BlockView so membership handlers can resolve series_id
        // for EventMetadata without a real projection.
        Ok(BlockView {
            id,
            season_id: SeasonId::from_uuid(Uuid::now_v7()),
            series_id: SeriesId::from_uuid(Uuid::now_v7()),
            number: 1,
            start_date: None,
            end_date: None,
            version: AggregateVersion::INITIAL,
            updated_at: chrono::Utc::now(),
        })
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
#[allow(dead_code)]
pub struct FakeEpisodeRepo;

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
#[allow(dead_code)]
pub struct FakeAuditRepo {
    pub entries: Arc<Mutex<Vec<AuditEntry>>>,
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
    async fn list_by_series(
        &self,
        _series_id: SeriesId,
        _limit: i64,
        _offset: i64,
    ) -> Result<Vec<AuditEntry>, DomainError> {
        Ok(Vec::new())
    }
}

#[derive(Clone, Default)]
#[allow(dead_code)]
pub struct FakeShootingDayCommands;

impl ShootingDayCommands for FakeShootingDayCommands {
    async fn create(
        &self,
        _actor: UserId,
        cmd: CreateShootingDay,
    ) -> Result<(ShootingDayId, AggregateVersion), DomainError> {
        Ok((cmd.id, AggregateVersion::INITIAL))
    }
    async fn rename(
        &self,
        _actor: UserId,
        _cmd: RenameShootingDay,
    ) -> Result<AggregateVersion, DomainError> {
        Ok(AggregateVersion::INITIAL.next())
    }
    async fn reschedule(
        &self,
        _actor: UserId,
        _cmd: RescheduleShootingDay,
    ) -> Result<AggregateVersion, DomainError> {
        Ok(AggregateVersion::INITIAL.next())
    }
    async fn reorder(
        &self,
        _actor: UserId,
        _cmd: ReorderShootingDay,
    ) -> Result<AggregateVersion, DomainError> {
        Ok(AggregateVersion::INITIAL.next())
    }
    async fn archive(
        &self,
        _actor: UserId,
        _cmd: ArchiveShootingDay,
    ) -> Result<AggregateVersion, DomainError> {
        Ok(AggregateVersion::INITIAL.next())
    }

    async fn wrap(
        &self,
        _actor: UserId,
        _cmd: WrapShootingDay,
    ) -> Result<AggregateVersion, DomainError> {
        Ok(AggregateVersion::INITIAL.next())
    }
}

#[derive(Clone, Default)]
#[allow(dead_code)]
pub struct FakeShootingDayRepo;

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

/// Placeholder photo storage for tests — panics if called.
#[derive(Clone, Default)]
#[allow(dead_code)]
pub struct FakePhotoStorage;

/// Placeholder photo commands for tests — panics if called.
#[derive(Clone, Default)]
#[allow(dead_code)]
pub struct FakePhotoCommands;

/// Placeholder photo repo for tests — panics if called.
#[derive(Clone, Default)]
#[allow(dead_code)]
pub struct FakePhotoRepo;

#[async_trait]
impl PhotoStorage for FakePhotoStorage {
    async fn store(
        &self,
        _id: PhotoId,
        _variant: PhotoVariant,
        _bytes: Vec<u8>,
        _content_type: String,
    ) -> Result<(), DomainError> {
        Ok(())
    }
    async fn fetch(&self, id: PhotoId, _variant: PhotoVariant) -> Result<PhotoBytes, DomainError> {
        Err(DomainError::NotFound(format!("Photo({id:?})")))
    }
    async fn delete_all(&self, _id: PhotoId) -> Result<(), DomainError> {
        Ok(())
    }
    async fn list(&self) -> Result<Vec<PhotoId>, DomainError> {
        Ok(Vec::new())
    }
}

#[async_trait]
impl PhotoCommands for FakePhotoCommands {
    async fn upload(
        &self,
        _actor: UserId,
        _cmd: UploadPhoto,
    ) -> Result<AggregateVersion, DomainError> {
        Ok(AggregateVersion::INITIAL)
    }
    async fn normalize_original(
        &self,
        _actor: UserId,
        _cmd: NormalizeOriginal,
    ) -> Result<AggregateVersion, DomainError> {
        Ok(AggregateVersion::INITIAL)
    }
    async fn generate_variant(
        &self,
        _actor: UserId,
        _cmd: GenerateVariant,
    ) -> Result<AggregateVersion, DomainError> {
        Ok(AggregateVersion::INITIAL)
    }
    async fn mark_variant_failed(
        &self,
        _actor: UserId,
        _cmd: MarkVariantFailed,
    ) -> Result<AggregateVersion, DomainError> {
        Ok(AggregateVersion::INITIAL)
    }
    async fn delete(
        &self,
        _actor: UserId,
        _cmd: DeletePhoto,
    ) -> Result<AggregateVersion, DomainError> {
        Ok(AggregateVersion::INITIAL)
    }
}

#[async_trait]
impl PhotoRepository for FakePhotoRepo {
    async fn find_by_id(&self, id: PhotoId) -> Result<PhotoView, DomainError> {
        Err(DomainError::NotFound(format!("Photo({id:?})")))
    }
    async fn list_known_ids(&self) -> Result<Vec<PhotoId>, DomainError> {
        Ok(Vec::new())
    }
    async fn count_links(&self, _photo_id: PhotoId) -> Result<u64, DomainError> {
        Ok(0)
    }
}

// ─── Fake SceneShootCommands ───────────────────────────────────────

#[derive(Clone, Default)]
#[allow(dead_code)]
pub struct FakeSceneShootCommands;

impl SceneShootCommands for FakeSceneShootCommands {
    async fn plan(
        &self,
        _actor: UserId,
        _cmd: PlanSceneShoot,
    ) -> Result<(SceneShootId, AggregateVersion), DomainError> {
        unreachable!("not used in authz tests")
    }
    async fn replan(
        &self,
        _actor: UserId,
        _cmd: ReplanSceneShoot,
    ) -> Result<AggregateVersion, DomainError> {
        unreachable!("not used in authz tests")
    }
    async fn start(
        &self,
        _actor: UserId,
        _cmd: StartSceneShoot,
    ) -> Result<AggregateVersion, DomainError> {
        unreachable!("not used in authz tests")
    }
    async fn set_actual_order(
        &self,
        _actor: UserId,
        _cmd: SetActualOrder,
    ) -> Result<AggregateVersion, DomainError> {
        unreachable!("not used in authz tests")
    }
    async fn finish(
        &self,
        _actor: UserId,
        _cmd: FinishSceneShoot,
    ) -> Result<AggregateVersion, DomainError> {
        unreachable!("not used in authz tests")
    }
    async fn skip(
        &self,
        _actor: UserId,
        _cmd: SkipSceneShoot,
    ) -> Result<AggregateVersion, DomainError> {
        unreachable!("not used in authz tests")
    }
    async fn add_note(
        &self,
        _actor: UserId,
        _cmd: AddSceneShootNote,
    ) -> Result<AggregateVersion, DomainError> {
        unreachable!("not used in authz tests")
    }
    async fn update_note(
        &self,
        _actor: UserId,
        _cmd: UpdateSceneShootNote,
    ) -> Result<AggregateVersion, DomainError> {
        unreachable!("not used in authz tests")
    }
    async fn remove_note(
        &self,
        _actor: UserId,
        _cmd: RemoveSceneShootNote,
    ) -> Result<AggregateVersion, DomainError> {
        unreachable!("not used in authz tests")
    }
    async fn link_continuity_photo(
        &self,
        _actor: UserId,
        _cmd: LinkContinuityPhoto,
    ) -> Result<AggregateVersion, DomainError> {
        unreachable!("not used in authz tests")
    }
    async fn unlink_continuity_photo(
        &self,
        _actor: UserId,
        _cmd: UnlinkContinuityPhoto,
    ) -> Result<AggregateVersion, DomainError> {
        unreachable!("not used in authz tests")
    }
}

// ─── Fake SceneShootRepository ─────────────────────────────────────

#[derive(Clone, Default)]
#[allow(dead_code)]
pub struct FakeSceneShootRepo;

impl SceneShootRepository for FakeSceneShootRepo {
    async fn find_by_id(&self, _id: SceneShootId) -> Result<SceneShootView, DomainError> {
        unreachable!("not used in authz tests")
    }
    async fn list_by_shooting_day(
        &self,
        _shooting_day_id: ShootingDayId,
    ) -> Result<Vec<SceneShootView>, DomainError> {
        unreachable!("not used in authz tests")
    }
    async fn find_by_scene_and_day(
        &self,
        _scene_id: Uuid,
        _shooting_day_id: ShootingDayId,
    ) -> Result<SceneShootView, DomainError> {
        unreachable!("not used in authz tests")
    }
    async fn list_by_scene(&self, _scene_id: Uuid) -> Result<Vec<SceneShootView>, DomainError> {
        unreachable!("not used in authz tests")
    }
}

// ─── Fake SceneShootReportRepository ───────────────────────────────

#[derive(Clone, Default)]
#[allow(dead_code)]
pub struct FakeSceneShootReportRepo;

impl SceneShootReportRepository for FakeSceneShootReportRepo {
    async fn dispo_report(
        &self,
        _shooting_day_id: ShootingDayId,
    ) -> Result<Vec<DispoRow>, DomainError> {
        unreachable!("not used in authz tests")
    }
    async fn shoot_day_report(
        &self,
        _shooting_day_id: ShootingDayId,
    ) -> Result<Vec<ShootDayRow>, DomainError> {
        unreachable!("not used in authz tests")
    }
    async fn soll_ist_report(
        &self,
        _shooting_day_id: ShootingDayId,
    ) -> Result<SollIstReport, DomainError> {
        unreachable!("not used in authz tests")
    }
}

/// A fake renderer that returns empty PDF bytes for handler tests.
#[derive(Debug)]
#[allow(dead_code)]
pub struct FakeReportRenderer;

#[async_trait::async_trait]
impl breakdown_core::reporting::ReportRenderer for FakeReportRenderer {
    async fn render(
        &self,
        _req: breakdown_core::reporting::ReportRenderRequest,
    ) -> std::result::Result<
        breakdown_core::reporting::ReportBytes,
        breakdown_core::reporting::ReportRenderError,
    > {
        Ok(breakdown_core::reporting::ReportBytes {
            kind: _req.kind,
            locale: _req.context.locale,
            pdf_bytes: Vec::new(),
            page_count: 0,
            content_type: "application/pdf",
            filename: format!("{}.pdf", _req.kind),
        })
    }
}

/// In-memory archival queue for handler tests (dedup by key).
#[derive(Clone, Default)]
#[allow(dead_code)]
pub struct FakeReportArchivalQueue {
    pub jobs: Arc<tokio::sync::Mutex<HashMap<String, EnqueueArchivalResult>>>,
}

#[async_trait::async_trait]
impl ReportArchivalQueue for FakeReportArchivalQueue {
    async fn enqueue(
        &self,
        req: EnqueueArchivalRequest,
    ) -> Result<EnqueueArchivalResult, ReportArchivalError> {
        let key = req.dedup_key();
        let mut guard = self.jobs.lock().await;
        if let Some(existing) = guard.get(&key) {
            return Ok(EnqueueArchivalResult {
                job_id: existing.job_id,
                already_enqueued: true,
                status: existing.status,
            });
        }
        let result = EnqueueArchivalResult {
            job_id: ReportJobId::new(),
            already_enqueued: false,
            status: ReportJobStatus::Pending,
        };
        guard.insert(key, result.clone());
        Ok(result)
    }

    async fn get(
        &self,
        job_id: ReportJobId,
    ) -> Result<Option<EnqueueArchivalResult>, ReportArchivalError> {
        let guard = self.jobs.lock().await;
        Ok(guard.values().find(|r| r.job_id == job_id).cloned())
    }
}

#[derive(Clone)]
#[allow(dead_code)]
pub struct FakePorts {
    pub scene_commands: FakeSceneCommands,
    pub scene_repo: FakeSceneRepo,
    pub character_commands: FakeCharacterCommands,
    pub character_repo: FakeCharacterRepo,
    pub costume_commands: FakeCostumeCommands,
    pub costume_repo: FakeCostumeRepo,
    pub costume_category_commands: FakeCostumeCategoryCommands,
    pub costume_category_repo: FakeCostumeCategoryRepo,
    pub season_commands: FakeSeasonCommands,
    pub season_repo: FakeSeasonRepo,
    pub block_commands: FakeBlockCommands,
    pub block_repo: FakeBlockRepo,
    pub episode_commands: FakeEpisodeCommands,
    pub episode_repo: FakeEpisodeRepo,
    pub membership_commands: FakeMembershipCommands,
    pub membership_repo: FakeMembershipRepo,
    pub audit_repo: FakeAuditRepo,
    pub shooting_day_commands: FakeShootingDayCommands,
    pub shooting_day_repo: FakeShootingDayRepo,
    #[allow(dead_code)]
    pub photo_storage: FakePhotoStorage,
    #[allow(dead_code)]
    pub scene_shoot_commands: FakeSceneShootCommands,
    pub scene_shoot_repo: FakeSceneShootRepo,
    pub scene_shoot_report_repo: FakeSceneShootReportRepo,
    pub photo_commands: FakePhotoCommands,
    #[allow(dead_code)]
    pub photo_repo: FakePhotoRepo,
    pub report_archival_queue: FakeReportArchivalQueue,
    #[allow(dead_code)]
    pub report_renderer: Arc<dyn breakdown_core::reporting::ReportRenderer>,
}

impl Default for FakePorts {
    fn default() -> Self {
        Self {
            scene_commands: Default::default(),
            scene_repo: Default::default(),
            character_commands: Default::default(),
            character_repo: Default::default(),
            costume_commands: Default::default(),
            costume_repo: Default::default(),
            costume_category_commands: Default::default(),
            costume_category_repo: Default::default(),
            season_commands: Default::default(),
            season_repo: Default::default(),
            block_commands: Default::default(),
            block_repo: Default::default(),
            episode_commands: Default::default(),
            episode_repo: Default::default(),
            membership_commands: Default::default(),
            membership_repo: Default::default(),
            audit_repo: Default::default(),
            shooting_day_commands: Default::default(),
            shooting_day_repo: Default::default(),
            photo_storage: Default::default(),
            scene_shoot_commands: Default::default(),
            scene_shoot_repo: Default::default(),
            scene_shoot_report_repo: Default::default(),
            photo_commands: Default::default(),
            photo_repo: Default::default(),
            report_archival_queue: Default::default(),
            report_renderer: Arc::new(FakeReportRenderer),
        }
    }
}

impl Ports for FakePorts {
    type SceneCommands = FakeSceneCommands;
    type SceneRepo = FakeSceneRepo;
    type CharacterCommands = FakeCharacterCommands;
    type CharacterRepo = FakeCharacterRepo;
    type CostumeCommands = FakeCostumeCommands;
    type CostumeRepo = FakeCostumeRepo;
    type CostumeCategoryCommands = FakeCostumeCategoryCommands;
    type CostumeCategoryRepo = FakeCostumeCategoryRepo;
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
    type PhotoStorage = FakePhotoStorage;
    type PhotoCommands = FakePhotoCommands;
    type PhotoRepo = FakePhotoRepo;
    type SceneShootCommands = FakeSceneShootCommands;
    type SceneShootRepo = FakeSceneShootRepo;
    type SceneShootReportRepo = FakeSceneShootReportRepo;
    type ReportArchivalQueue = FakeReportArchivalQueue;
    type ReportRenderer = Arc<dyn breakdown_core::reporting::ReportRenderer>;

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
    fn costume_category_commands(&self) -> &Self::CostumeCategoryCommands {
        &self.costume_category_commands
    }
    fn costume_category_repo(&self) -> &Self::CostumeCategoryRepo {
        &self.costume_category_repo
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
    fn photo_storage(&self) -> &Self::PhotoStorage {
        &self.photo_storage
    }
    fn photo_commands(&self) -> &Self::PhotoCommands {
        &self.photo_commands
    }
    fn photo_repo(&self) -> &Self::PhotoRepo {
        &self.photo_repo
    }
    fn scene_shoot_commands(&self) -> &Self::SceneShootCommands {
        &self.scene_shoot_commands
    }
    fn scene_shoot_repo(&self) -> &Self::SceneShootRepo {
        &self.scene_shoot_repo
    }
    fn scene_shoot_report_repo(&self) -> &Self::SceneShootReportRepo {
        &self.scene_shoot_report_repo
    }
    fn report_archival_queue(&self) -> &Self::ReportArchivalQueue {
        &self.report_archival_queue
    }
    fn report_renderer(&self) -> &Self::ReportRenderer {
        &self.report_renderer
    }
    fn report_renderer_ref(&self) -> &dyn breakdown_core::reporting::ReportRenderer {
        &*self.report_renderer
    }
}
