// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: gpt-5.6-luna (opencode-go)
// Co-authored-by: deepseek-v4-flash (opencode-go)
// Co-authored-by: longcat-2.0-free (opencode)

//! AppState – Composition-Root (manuelles DI)
//!
//! `AppState` is generic over a `Ports` implementation so that unit tests can
//! substitute hand-written fakes without spinning up SierraDB or Postgres.

// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: mimo-v2.5 (opencode-go)

use std::sync::Arc;

use crate::auth::authorization::MembershipAuthorizationPolicy;
use breakdown_core::ai::{
    AiConfigCommands, AiConfigRepository, AiImportMappingRepository, AiImportQueue,
};
use breakdown_core::audit::AuditRepository;
use breakdown_core::block::{BlockCommands, BlockRepository};
use breakdown_core::character::{CharacterCommands, CharacterRepository};
use breakdown_core::costume::{CostumeCommands, CostumeRepository};
use breakdown_core::costume_category::{CostumeCategoryCommands, CostumeCategoryRepository};
use breakdown_core::episode::{EpisodeCommands, EpisodeRepository};
use breakdown_core::membership::policy::AuthorizationPolicy;
use breakdown_core::membership::{MembershipCommands, MembershipRepository};
use breakdown_core::photo::ports::{PhotoCommands, PhotoRepository, PhotoStorage};
use breakdown_core::reporting::{ReportArchivalQueue, ReportRenderer};
use breakdown_core::scene::{SceneCommands, SceneRepository};
use breakdown_core::scene_shoot::{
    SceneShootCommands, SceneShootReportRepository, SceneShootRepository,
};
use breakdown_core::season::{SeasonCommands, SeasonRepository};
use breakdown_core::settings::{CredentialVault, SettingsCommands, SettingsRepository};
use breakdown_core::shooting_day::{ShootingDayCommands, ShootingDayRepository};
use infra::ai::{
    AiDocumentSource, AiDocumentStore, AiPreviewStore, PgAiImportMappingRepository, PgAiImportQueue,
};
use infra::event_store::{
    AiConfigCommandsImpl, BlockCommandsImpl, CharacterCommandsImpl, CostumeCategoryCommandsImpl,
    CostumeCommandsImpl, EpisodeCommandsImpl, MembershipCommandsImpl, PhotoCommandsImpl,
    SceneCommandsImpl, SceneShootCommandsImpl, SeasonCommandsImpl, SettingsCommandsImpl,
    ShootingDayCommandsImpl,
};
use infra::photo::repository::PhotoRepositoryImpl;
use infra::photo::storage::OpenDalPhotoStorage;
use infra::queries::{
    AiConfigRepositoryImpl, AuditRepositoryImpl, BlockRepositoryImpl, CharacterRepositoryImpl,
    CostumeCategoryRepositoryImpl, CostumeRepositoryImpl, EpisodeRepositoryImpl,
    MembershipRepositoryImpl, SceneRepositoryImpl, SceneShootReportRepositoryImpl,
    SceneShootRepositoryImpl, SeasonRepositoryImpl, SettingsRepositoryImpl,
    ShootingDayRepositoryImpl,
};
use infra::reporting::PgReportArchivalQueue;
use infra::vault::VaultClient;

/// The hexagonal seam surface used by API handlers. Production implements it
/// with the concrete `kameo_es` write adapters and `sqlx` read adapters.
pub trait Ports: Clone + Send + Sync + 'static {
    // `+ Clone` on the write-side command ports: the AI apply handlers hand
    // owned clones to the infra apply workers (`ApplyWorker`,
    // `ScheduleApplyWorker`), which take `Arc<C>`. Without the bound a generic
    // `.clone()` would silently clone the *reference* instead of the adapter.
    type SceneCommands: SceneCommands + Clone;
    type SceneRepo: SceneRepository;
    type ShootingDayCommands: ShootingDayCommands + Clone;
    type ShootingDayRepo: ShootingDayRepository;
    type CharacterCommands: CharacterCommands;
    type CharacterRepo: CharacterRepository;
    type CostumeCommands: CostumeCommands;
    type CostumeRepo: CostumeRepository;
    type CostumeCategoryCommands: CostumeCategoryCommands;
    type CostumeCategoryRepo: CostumeCategoryRepository;
    type SeasonCommands: SeasonCommands;
    type SeasonRepo: SeasonRepository;
    type BlockCommands: BlockCommands;
    type BlockRepo: BlockRepository;
    type EpisodeCommands: EpisodeCommands;
    type EpisodeRepo: EpisodeRepository;
    type MembershipCommands: MembershipCommands;
    type MembershipRepo: MembershipRepository;
    type SettingsCommands: SettingsCommands;
    type SettingsRepo: SettingsRepository;
    type CredentialVault: CredentialVault;
    type AuditRepo: AuditRepository;
    type PhotoStorage: PhotoStorage;
    type PhotoCommands: PhotoCommands;
    type PhotoRepo: PhotoRepository;
    type SceneShootCommands: SceneShootCommands + Clone;
    type SceneShootRepo: SceneShootRepository;
    type SceneShootReportRepo: SceneShootReportRepository;
    type ReportArchivalQueue: ReportArchivalQueue;
    type ReportRenderer: Send + Sync;
    // --- AI import seam -------------------------------------------------
    // The AI import dependencies are part of the same hexagonal seam as every
    // other port, so handlers stay generic over `P: Ports` and tests can
    // substitute fakes without a PostgreSQL-backed adapter (issue #176).
    type AiConfigCommands: AiConfigCommands;
    type AiConfigRepo: AiConfigRepository;
    type AiImportQueue: AiImportQueue + Clone;
    type AiImportMappingRepo: AiImportMappingRepository + Clone;
    /// `?Sized` so production can keep its `Arc<dyn AiPreviewStore>` handle
    /// (chosen at boot between the durable S3 and the in-memory backend)
    /// while tests bind a concrete fake.
    type AiPreviewStore: AiPreviewStore + ?Sized;
    type AiDocumentStore: AiDocumentStore + ?Sized;
    type AiDocumentSource: AiDocumentSource + ?Sized;

    fn scene_commands(&self) -> &Self::SceneCommands;
    fn scene_repo(&self) -> &Self::SceneRepo;
    fn shooting_day_commands(&self) -> &Self::ShootingDayCommands;
    fn shooting_day_repo(&self) -> &Self::ShootingDayRepo;
    fn scene_shoot_commands(&self) -> &Self::SceneShootCommands;
    fn scene_shoot_repo(&self) -> &Self::SceneShootRepo;
    fn scene_shoot_report_repo(&self) -> &Self::SceneShootReportRepo;
    fn character_commands(&self) -> &Self::CharacterCommands;
    fn character_repo(&self) -> &Self::CharacterRepo;
    fn costume_commands(&self) -> &Self::CostumeCommands;
    fn costume_repo(&self) -> &Self::CostumeRepo;
    fn costume_category_commands(&self) -> &Self::CostumeCategoryCommands;
    fn costume_category_repo(&self) -> &Self::CostumeCategoryRepo;
    fn season_commands(&self) -> &Self::SeasonCommands;
    fn season_repo(&self) -> &Self::SeasonRepo;
    fn block_commands(&self) -> &Self::BlockCommands;
    fn block_repo(&self) -> &Self::BlockRepo;
    fn episode_commands(&self) -> &Self::EpisodeCommands;
    fn episode_repo(&self) -> &Self::EpisodeRepo;
    fn membership_commands(&self) -> &Self::MembershipCommands;
    fn membership_repo(&self) -> &Self::MembershipRepo;
    fn settings_commands(&self) -> &Self::SettingsCommands;
    fn settings_repo(&self) -> &Self::SettingsRepo;
    fn credential_vault(&self) -> &Self::CredentialVault;
    fn audit_repo(&self) -> &Self::AuditRepo;
    fn photo_storage(&self) -> &Self::PhotoStorage;
    fn photo_commands(&self) -> &Self::PhotoCommands;
    fn photo_repo(&self) -> &Self::PhotoRepo;
    fn report_archival_queue(&self) -> &Self::ReportArchivalQueue;
    fn report_renderer(&self) -> &Self::ReportRenderer;
    fn report_renderer_ref(&self) -> &dyn ReportRenderer;
    fn ai_config_commands(&self) -> &Self::AiConfigCommands;
    fn ai_config_repo(&self) -> &Self::AiConfigRepo;
    fn ai_import_queue(&self) -> &Self::AiImportQueue;
    fn ai_import_mapping(&self) -> &Self::AiImportMappingRepo;
    fn ai_preview_store(&self) -> &Self::AiPreviewStore;
    fn ai_document_store(&self) -> &Self::AiDocumentStore;
    fn ai_document_source(&self) -> &Self::AiDocumentSource;
}

/// Shared state handed to every Axum handler.
#[derive(Clone)]
pub struct AppState<P: Ports> {
    pub ports: P,
    /// The membership-backed [`AuthorizationPolicy`] used by handlers on
    /// `Authenticated`-only privileged routes (AI import gates). Constructed
    /// once at state-build time from the same read model the middleware
    /// policy consults, so handler-internal gates never diverge from the
    /// composition root. `main.rs` shares this `Arc` with the middleware
    /// [`AuthorizationState`] instead of rebuilding a second policy.
    pub authorization_policy: Arc<dyn AuthorizationPolicy>,
    /// Rollout switch for AI import routes/workers. It is explicitly enabled
    /// by `AI_IMPORT_ENABLED`; the default is safe/off.
    pub ai_import_enabled: bool,
    /// AI document size bound, resolved once from `AiImportFeature` at state
    /// construction so the handler and the extractor share one value.
    pub ai_import_max_document_bytes: u64,
}

impl<P: Ports> std::fmt::Debug for AppState<P> {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("AppState")
            .field("ai_import_enabled", &self.ai_import_enabled)
            .field(
                "ai_import_max_document_bytes",
                &self.ai_import_max_document_bytes,
            )
            .finish_non_exhaustive()
    }
}

impl<P: Ports> AppState<P>
where
    P::MembershipRepo: Clone,
{
    /// Environment-driven production entry point: reads `AI_IMPORT_ENABLED`
    /// and the document bound once at construction.
    pub fn new(ports: P) -> Self {
        let feature = infra::ai::AiImportFeature::from_env();
        Self::with_ai_import(ports, feature.enabled, feature.bounds.max_document_bytes)
    }

    /// Builds state with explicit rollout values, bypassing the process
    /// environment — lets tests exercise both `ai_import_enabled` branches
    /// deterministically (process env is global and `set_var` is unsafe in
    /// Rust 2024).
    pub fn with_ai_import(
        ports: P,
        ai_import_enabled: bool,
        ai_import_max_document_bytes: u64,
    ) -> Self {
        let authorization_policy: Arc<dyn AuthorizationPolicy> = Arc::new(
            MembershipAuthorizationPolicy::new(Arc::new(ports.membership_repo().clone())),
        );
        Self {
            ports,
            authorization_policy,
            ai_import_enabled,
            ai_import_max_document_bytes,
        }
    }
}

/// The AI import dependency group handed to [`ProductionPorts::new`].
///
/// Grouping the seven AI adapters into one value keeps the composition-root
/// constructor readable (issue #176). It is a pure parameter bundle: no
/// behavior, no defaults, and the fields are moved straight into
/// [`ProductionPorts`].
#[derive(Clone)]
pub struct AiPorts {
    pub config_commands: AiConfigCommandsImpl,
    pub config_repo: AiConfigRepositoryImpl,
    pub import_queue: PgAiImportQueue,
    pub import_mapping: PgAiImportMappingRepository,
    pub preview_store: Arc<dyn AiPreviewStore + Send + Sync>,
    pub document_store: Arc<dyn AiDocumentStore + Send + Sync>,
    pub document_source: Arc<dyn AiDocumentSource + Send + Sync>,
}

/// Production port bundle assembled in `main.rs`.
#[derive(Clone)]
pub struct ProductionPorts {
    scene_commands: SceneCommandsImpl,
    scene_repo: SceneRepositoryImpl,
    shooting_day_commands: ShootingDayCommandsImpl,
    shooting_day_repo: ShootingDayRepositoryImpl,
    character_commands: CharacterCommandsImpl,
    character_repo: CharacterRepositoryImpl,
    costume_commands: CostumeCommandsImpl,
    costume_repo: CostumeRepositoryImpl,
    costume_category_commands: CostumeCategoryCommandsImpl,
    costume_category_repo: CostumeCategoryRepositoryImpl,
    season_commands: SeasonCommandsImpl,
    season_repo: SeasonRepositoryImpl,
    block_commands: BlockCommandsImpl,
    block_repo: BlockRepositoryImpl,
    episode_commands: EpisodeCommandsImpl,
    episode_repo: EpisodeRepositoryImpl,
    membership_commands: MembershipCommandsImpl,
    membership_repo: MembershipRepositoryImpl,
    settings_commands: SettingsCommandsImpl,
    settings_repo: SettingsRepositoryImpl,
    credential_vault: VaultClient,
    audit_repo: AuditRepositoryImpl,
    photo_storage: OpenDalPhotoStorage,
    photo_commands: PhotoCommandsImpl,
    photo_repo: PhotoRepositoryImpl,
    scene_shoot_commands: SceneShootCommandsImpl,
    scene_shoot_repo: SceneShootRepositoryImpl,
    scene_shoot_report_repo: SceneShootReportRepositoryImpl,
    report_archival_queue: PgReportArchivalQueue,
    report_renderer: Arc<dyn ReportRenderer>,
    ai_config_commands: AiConfigCommandsImpl,
    ai_config_repo: AiConfigRepositoryImpl,
    ai_import_queue: PgAiImportQueue,
    ai_import_mapping: PgAiImportMappingRepository,
    ai_preview_store: Arc<dyn AiPreviewStore + Send + Sync>,
    ai_document_store: Arc<dyn AiDocumentStore + Send + Sync>,
    ai_document_source: Arc<dyn AiDocumentSource + Send + Sync>,
}

impl ProductionPorts {
    // The composition root wires every adapter explicitly (poor man's DI); the
    // parameter count is the honest shape of that wiring. The AI group is
    // already bundled into `AiPorts` (issue #176).
    #[allow(clippy::too_many_arguments)]
    pub fn new(
        scene_commands: SceneCommandsImpl,
        scene_repo: SceneRepositoryImpl,
        shooting_day_commands: ShootingDayCommandsImpl,
        shooting_day_repo: ShootingDayRepositoryImpl,
        character_commands: CharacterCommandsImpl,
        character_repo: CharacterRepositoryImpl,
        costume_commands: CostumeCommandsImpl,
        costume_repo: CostumeRepositoryImpl,
        costume_category_commands: CostumeCategoryCommandsImpl,
        costume_category_repo: CostumeCategoryRepositoryImpl,
        season_commands: SeasonCommandsImpl,
        season_repo: SeasonRepositoryImpl,
        block_commands: BlockCommandsImpl,
        block_repo: BlockRepositoryImpl,
        episode_commands: EpisodeCommandsImpl,
        episode_repo: EpisodeRepositoryImpl,
        membership_commands: MembershipCommandsImpl,
        membership_repo: MembershipRepositoryImpl,
        settings_commands: SettingsCommandsImpl,
        settings_repo: SettingsRepositoryImpl,
        credential_vault: VaultClient,
        audit_repo: AuditRepositoryImpl,
        photo_storage: OpenDalPhotoStorage,
        photo_commands: PhotoCommandsImpl,
        photo_repo: PhotoRepositoryImpl,
        scene_shoot_commands: SceneShootCommandsImpl,
        scene_shoot_repo: SceneShootRepositoryImpl,
        scene_shoot_report_repo: SceneShootReportRepositoryImpl,
        report_archival_queue: PgReportArchivalQueue,
        report_renderer: Arc<dyn ReportRenderer>,
        ai: AiPorts,
    ) -> Self {
        let AiPorts {
            config_commands: ai_config_commands,
            config_repo: ai_config_repo,
            import_queue: ai_import_queue,
            import_mapping: ai_import_mapping,
            preview_store: ai_preview_store,
            document_store: ai_document_store,
            document_source: ai_document_source,
        } = ai;
        Self {
            scene_commands,
            scene_repo,
            shooting_day_commands,
            shooting_day_repo,
            character_commands,
            character_repo,
            costume_commands,
            costume_repo,
            costume_category_commands,
            costume_category_repo,
            season_commands,
            season_repo,
            block_commands,
            block_repo,
            episode_commands,
            episode_repo,
            membership_commands,
            membership_repo,
            settings_commands,
            settings_repo,
            credential_vault,
            audit_repo,
            photo_storage,
            photo_commands,
            photo_repo,
            scene_shoot_commands,
            scene_shoot_repo,
            scene_shoot_report_repo,
            report_archival_queue,
            report_renderer,
            ai_config_commands,
            ai_config_repo,
            ai_import_queue,
            ai_import_mapping,
            ai_preview_store,
            ai_document_store,
            ai_document_source,
        }
    }
}

impl Ports for ProductionPorts {
    type SceneCommands = SceneCommandsImpl;
    type SceneRepo = SceneRepositoryImpl;
    type ShootingDayCommands = ShootingDayCommandsImpl;
    type ShootingDayRepo = ShootingDayRepositoryImpl;
    type CharacterCommands = CharacterCommandsImpl;
    type CharacterRepo = CharacterRepositoryImpl;
    type CostumeCommands = CostumeCommandsImpl;
    type CostumeRepo = CostumeRepositoryImpl;
    type CostumeCategoryCommands = CostumeCategoryCommandsImpl;
    type CostumeCategoryRepo = CostumeCategoryRepositoryImpl;
    type SeasonCommands = SeasonCommandsImpl;
    type SeasonRepo = SeasonRepositoryImpl;
    type BlockCommands = BlockCommandsImpl;
    type BlockRepo = BlockRepositoryImpl;
    type EpisodeCommands = EpisodeCommandsImpl;
    type EpisodeRepo = EpisodeRepositoryImpl;
    type MembershipCommands = MembershipCommandsImpl;
    type MembershipRepo = MembershipRepositoryImpl;
    type SettingsCommands = SettingsCommandsImpl;
    type SettingsRepo = SettingsRepositoryImpl;
    type CredentialVault = VaultClient;
    type AuditRepo = AuditRepositoryImpl;
    type PhotoStorage = OpenDalPhotoStorage;
    type PhotoCommands = PhotoCommandsImpl;
    type PhotoRepo = PhotoRepositoryImpl;
    type SceneShootCommands = SceneShootCommandsImpl;
    type SceneShootRepo = SceneShootRepositoryImpl;
    type SceneShootReportRepo = SceneShootReportRepositoryImpl;
    type ReportArchivalQueue = PgReportArchivalQueue;
    type ReportRenderer = Arc<dyn ReportRenderer>;
    type AiConfigCommands = AiConfigCommandsImpl;
    type AiConfigRepo = AiConfigRepositoryImpl;
    type AiImportQueue = PgAiImportQueue;
    type AiImportMappingRepo = PgAiImportMappingRepository;
    // The unsized `dyn` projections keep the boot-time choice between the
    // durable S3 backend and the in-memory dev store behind one port type.
    type AiPreviewStore = dyn AiPreviewStore + Send + Sync;
    type AiDocumentStore = dyn AiDocumentStore + Send + Sync;
    type AiDocumentSource = dyn AiDocumentSource + Send + Sync;

    fn scene_commands(&self) -> &Self::SceneCommands {
        &self.scene_commands
    }
    fn scene_repo(&self) -> &Self::SceneRepo {
        &self.scene_repo
    }
    fn shooting_day_commands(&self) -> &Self::ShootingDayCommands {
        &self.shooting_day_commands
    }
    fn shooting_day_repo(&self) -> &Self::ShootingDayRepo {
        &self.shooting_day_repo
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
    fn settings_commands(&self) -> &Self::SettingsCommands {
        &self.settings_commands
    }
    fn settings_repo(&self) -> &Self::SettingsRepo {
        &self.settings_repo
    }
    fn credential_vault(&self) -> &Self::CredentialVault {
        &self.credential_vault
    }
    fn audit_repo(&self) -> &Self::AuditRepo {
        &self.audit_repo
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
    fn report_renderer_ref(&self) -> &dyn ReportRenderer {
        &*self.report_renderer
    }
    fn ai_config_commands(&self) -> &Self::AiConfigCommands {
        &self.ai_config_commands
    }
    fn ai_config_repo(&self) -> &Self::AiConfigRepo {
        &self.ai_config_repo
    }
    fn ai_import_queue(&self) -> &Self::AiImportQueue {
        &self.ai_import_queue
    }
    fn ai_import_mapping(&self) -> &Self::AiImportMappingRepo {
        &self.ai_import_mapping
    }
    fn ai_preview_store(&self) -> &Self::AiPreviewStore {
        self.ai_preview_store.as_ref()
    }
    fn ai_document_store(&self) -> &Self::AiDocumentStore {
        self.ai_document_store.as_ref()
    }
    fn ai_document_source(&self) -> &Self::AiDocumentSource {
        self.ai_document_source.as_ref()
    }
}
