// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_import

import 'package:one_of_serializer/any_of_serializer.dart';
import 'package:one_of_serializer/one_of_serializer.dart';
import 'package:built_collection/built_collection.dart';
import 'package:built_value/json_object.dart';
import 'package:built_value/serializer.dart';
import 'package:built_value/standard_json_plugin.dart';
import 'package:built_value/iso_8601_date_time_serializer.dart';
import 'package:breakdown_api/src/date_serializer.dart';
import 'package:breakdown_api/src/model/date.dart';

import 'package:breakdown_api/src/model/add_note_request.dart';
import 'package:breakdown_api/src/model/add_outfit_piece_request.dart';
import 'package:breakdown_api/src/model/add_piece_detail_request.dart';
import 'package:breakdown_api/src/model/add_piece_to_season_request.dart';
import 'package:breakdown_api/src/model/add_scene_outfit_beat_request.dart';
import 'package:breakdown_api/src/model/aggregate_soll_ist_diff_row.dart';
import 'package:breakdown_api/src/model/aggregate_soll_ist_report.dart';
import 'package:breakdown_api/src/model/ai_config_view.dart';
import 'package:breakdown_api/src/model/ai_import_attempt.dart';
import 'package:breakdown_api/src/model/ai_import_defaults.dart';
import 'package:breakdown_api/src/model/ai_import_job.dart';
import 'package:breakdown_api/src/model/ai_import_job_response.dart';
import 'package:breakdown_api/src/model/ai_import_preview_response.dart';
import 'package:breakdown_api/src/model/ai_import_progress.dart';
import 'package:breakdown_api/src/model/ai_import_stage.dart';
import 'package:breakdown_api/src/model/ai_import_target.dart';
import 'package:breakdown_api/src/model/ai_preview_payload.dart';
import 'package:breakdown_api/src/model/ai_preview_payload_one_of.dart';
import 'package:breakdown_api/src/model/ai_preview_payload_one_of1.dart';
import 'package:breakdown_api/src/model/ai_preview_payload_one_of2.dart';
import 'package:breakdown_api/src/model/ai_provider_info.dart';
import 'package:breakdown_api/src/model/appearance_outfit_view.dart';
import 'package:breakdown_api/src/model/applied_episode.dart';
import 'package:breakdown_api/src/model/apply_ai_import_request.dart';
import 'package:breakdown_api/src/model/apply_ai_import_response.dart';
import 'package:breakdown_api/src/model/apply_episode_group_request.dart';
import 'package:breakdown_api/src/model/apply_mapping.dart';
import 'package:breakdown_api/src/model/apply_mapping_decision.dart';
import 'package:breakdown_api/src/model/apply_mapping_decision_one_of.dart';
import 'package:breakdown_api/src/model/apply_mapping_decision_one_of_update.dart';
import 'package:breakdown_api/src/model/apply_shooting_day_request.dart';
import 'package:breakdown_api/src/model/assign_character_request.dart';
import 'package:breakdown_api/src/model/audit_entry.dart';
import 'package:breakdown_api/src/model/block_view.dart';
import 'package:breakdown_api/src/model/character_appearance_view.dart';
import 'package:breakdown_api/src/model/character_category.dart';
import 'package:breakdown_api/src/model/character_measurements.dart';
import 'package:breakdown_api/src/model/character_view.dart';
import 'package:breakdown_api/src/model/checkpoint_progress.dart';
import 'package:breakdown_api/src/model/contact_info.dart';
import 'package:breakdown_api/src/model/cost_breakdown.dart';
import 'package:breakdown_api/src/model/cost_display_preference.dart';
import 'package:breakdown_api/src/model/cost_status.dart';
import 'package:breakdown_api/src/model/costume_category_view.dart';
import 'package:breakdown_api/src/model/create_ai_config_request.dart';
import 'package:breakdown_api/src/model/create_block_request.dart';
import 'package:breakdown_api/src/model/create_character_request.dart';
import 'package:breakdown_api/src/model/create_costume_category_request.dart';
import 'package:breakdown_api/src/model/create_credential_request.dart';
import 'package:breakdown_api/src/model/create_episode_request.dart';
import 'package:breakdown_api/src/model/create_outfit_request.dart';
import 'package:breakdown_api/src/model/create_outfit_variant_request.dart';
import 'package:breakdown_api/src/model/create_piece_request.dart';
import 'package:breakdown_api/src/model/create_scene_request.dart';
import 'package:breakdown_api/src/model/create_season_request.dart';
import 'package:breakdown_api/src/model/create_shooting_day_request.dart';
import 'package:breakdown_api/src/model/credential_binding_state.dart';
import 'package:breakdown_api/src/model/currency.dart';
import 'package:breakdown_api/src/model/dead_letter_entry.dart';
import 'package:breakdown_api/src/model/decision_outcome.dart';
import 'package:breakdown_api/src/model/decision_rubric.dart';
import 'package:breakdown_api/src/model/decision_telemetry.dart';
import 'package:breakdown_api/src/model/dispo_row.dart';
import 'package:breakdown_api/src/model/document_kind.dart';
import 'package:breakdown_api/src/model/draft_character.dart';
import 'package:breakdown_api/src/model/draft_episode.dart';
import 'package:breakdown_api/src/model/draft_outfit.dart';
import 'package:breakdown_api/src/model/draft_outfit_candidate.dart';
import 'package:breakdown_api/src/model/draft_outfit_origin.dart';
import 'package:breakdown_api/src/model/draft_outfit_provenance.dart';
import 'package:breakdown_api/src/model/draft_piece.dart';
import 'package:breakdown_api/src/model/draft_scene.dart';
import 'package:breakdown_api/src/model/draft_shooting_day.dart';
import 'package:breakdown_api/src/model/energy_cost_breakdown.dart';
import 'package:breakdown_api/src/model/episode_target.dart';
import 'package:breakdown_api/src/model/episode_target_one_of.dart';
import 'package:breakdown_api/src/model/episode_target_one_of1.dart';
import 'package:breakdown_api/src/model/episode_view.dart';
import 'package:breakdown_api/src/model/finish_scene_shoot_request.dart';
import 'package:breakdown_api/src/model/g_drive_credential_request.dart';
import 'package:breakdown_api/src/model/g_drive_credential_update_request.dart';
import 'package:breakdown_api/src/model/grant_role_request.dart';
import 'package:breakdown_api/src/model/health_entry.dart';
import 'package:breakdown_api/src/model/health_report.dart';
import 'package:breakdown_api/src/model/health_status.dart';
import 'package:breakdown_api/src/model/id_version_response.dart';
import 'package:breakdown_api/src/model/image_cost_breakdown.dart';
import 'package:breakdown_api/src/model/invite_member_request.dart';
import 'package:breakdown_api/src/model/job_status.dart';
import 'package:breakdown_api/src/model/job_telemetry_summary.dart';
import 'package:breakdown_api/src/model/link_continuity_photo_request.dart';
import 'package:breakdown_api/src/model/link_shooting_day_response.dart';
import 'package:breakdown_api/src/model/llm_provider.dart';
import 'package:breakdown_api/src/model/manual_archive_job_result.dart';
import 'package:breakdown_api/src/model/manual_archive_response.dart';
import 'package:breakdown_api/src/model/membership_state_kind.dart';
import 'package:breakdown_api/src/model/membership_view.dart';
import 'package:breakdown_api/src/model/merged_preview.dart';
import 'package:breakdown_api/src/model/merged_scene.dart';
import 'package:breakdown_api/src/model/meta_credits_entry.dart';
import 'package:breakdown_api/src/model/meta_credits_response.dart';
import 'package:breakdown_api/src/model/meta_versions_response.dart';
import 'package:breakdown_api/src/model/model_info.dart';
import 'package:breakdown_api/src/model/model_pricing.dart';
import 'package:breakdown_api/src/model/outfit_continuity_candidate.dart';
import 'package:breakdown_api/src/model/outfit_continuity_selection.dart';
import 'package:breakdown_api/src/model/outfit_decision.dart';
import 'package:breakdown_api/src/model/outfit_photo_view.dart';
import 'package:breakdown_api/src/model/outfit_piece_view.dart';
import 'package:breakdown_api/src/model/outfit_view.dart';
import 'package:breakdown_api/src/model/photo_binding.dart';
import 'package:breakdown_api/src/model/photo_binding_one_of.dart';
import 'package:breakdown_api/src/model/photo_binding_one_of1.dart';
import 'package:breakdown_api/src/model/photo_binding_one_of1_outfit.dart';
import 'package:breakdown_api/src/model/photo_binding_one_of2.dart';
import 'package:breakdown_api/src/model/photo_binding_one_of2_continuity.dart';
import 'package:breakdown_api/src/model/photo_binding_one_of_piece.dart';
import 'package:breakdown_api/src/model/photo_bytes_query.dart';
import 'package:breakdown_api/src/model/photo_variant.dart';
import 'package:breakdown_api/src/model/photo_variant_view.dart';
import 'package:breakdown_api/src/model/photo_view.dart';
import 'package:breakdown_api/src/model/piece_detail_request.dart';
import 'package:breakdown_api/src/model/piece_detail_view.dart';
import 'package:breakdown_api/src/model/piece_photo_view.dart';
import 'package:breakdown_api/src/model/piece_view.dart';
import 'package:breakdown_api/src/model/plan_scene_shoot_request.dart';
import 'package:breakdown_api/src/model/pricing_source.dart';
import 'package:breakdown_api/src/model/problem_details.dart';
import 'package:breakdown_api/src/model/projector_health_snapshot.dart';
import 'package:breakdown_api/src/model/rename_episode_request.dart';
import 'package:breakdown_api/src/model/rename_outfit_request.dart';
import 'package:breakdown_api/src/model/rename_piece_request.dart';
import 'package:breakdown_api/src/model/rename_season_request.dart';
import 'package:breakdown_api/src/model/replan_scene_shoot_request.dart';
import 'package:breakdown_api/src/model/revoke_ai_config_request.dart';
import 'package:breakdown_api/src/model/role.dart';
import 'package:breakdown_api/src/model/scene_details.dart';
import 'package:breakdown_api/src/model/scene_outfit_beat_view.dart';
import 'package:breakdown_api/src/model/scene_shoot_status.dart';
import 'package:breakdown_api/src/model/scene_shoot_view.dart';
import 'package:breakdown_api/src/model/scene_source.dart';
import 'package:breakdown_api/src/model/scene_source_one_of.dart';
import 'package:breakdown_api/src/model/scene_source_one_of_ai_extracted.dart';
import 'package:breakdown_api/src/model/scene_view.dart';
import 'package:breakdown_api/src/model/schedule_scene_request.dart';
import 'package:breakdown_api/src/model/script_context.dart';
import 'package:breakdown_api/src/model/season_membership_dto.dart';
import 'package:breakdown_api/src/model/season_view.dart';
import 'package:breakdown_api/src/model/serialized_note.dart';
import 'package:breakdown_api/src/model/series_membership_dto.dart';
import 'package:breakdown_api/src/model/set_actual_order_request.dart';
import 'package:breakdown_api/src/model/set_piece_category_request.dart';
import 'package:breakdown_api/src/model/settings_view.dart';
import 'package:breakdown_api/src/model/shoot_day_row.dart';
import 'package:breakdown_api/src/model/shooting_day_source.dart';
import 'package:breakdown_api/src/model/shooting_day_view.dart';
import 'package:breakdown_api/src/model/shooting_schedule.dart';
import 'package:breakdown_api/src/model/shooting_schedule_row.dart';
import 'package:breakdown_api/src/model/skip_scene_shoot_request.dart';
import 'package:breakdown_api/src/model/soll_ist_diff_row.dart';
import 'package:breakdown_api/src/model/soll_ist_report.dart';
import 'package:breakdown_api/src/model/source_format.dart';
import 'package:breakdown_api/src/model/start_scene_shoot_request.dart';
import 'package:breakdown_api/src/model/token_cost_breakdown.dart';
import 'package:breakdown_api/src/model/unapplied_outfit.dart';
import 'package:breakdown_api/src/model/unapplied_outfit_reason.dart';
import 'package:breakdown_api/src/model/uncertainty.dart';
import 'package:breakdown_api/src/model/uncertainty_acknowledgement.dart';
import 'package:breakdown_api/src/model/uncertainty_kind.dart';
import 'package:breakdown_api/src/model/update_ai_config_request.dart';
import 'package:breakdown_api/src/model/update_block_time_span_request.dart';
import 'package:breakdown_api/src/model/update_character_category_request.dart';
import 'package:breakdown_api/src/model/update_contact_info_request.dart';
import 'package:breakdown_api/src/model/update_costume_category_request.dart';
import 'package:breakdown_api/src/model/update_measurements_request.dart';
import 'package:breakdown_api/src/model/update_note_request.dart';
import 'package:breakdown_api/src/model/update_outfit_notes_request.dart';
import 'package:breakdown_api/src/model/update_piece_detail_request.dart';
import 'package:breakdown_api/src/model/update_piece_notes_request.dart';
import 'package:breakdown_api/src/model/update_scene_details_request.dart';
import 'package:breakdown_api/src/model/update_scene_outfit_beat_request.dart';
import 'package:breakdown_api/src/model/update_shooting_day_request.dart';
import 'package:breakdown_api/src/model/variant_status.dart';
import 'package:breakdown_api/src/model/version_request.dart';
import 'package:breakdown_api/src/model/wrap_shooting_day_request.dart';

part 'serializers.g.dart';

@SerializersFor([
  AddNoteRequest,
  AddOutfitPieceRequest,
  AddPieceDetailRequest,
  AddPieceToSeasonRequest,
  AddSceneOutfitBeatRequest,
  AggregateSollIstDiffRow,
  AggregateSollIstReport,
  AiConfigView,
  AiImportAttempt,
  AiImportDefaults,
  AiImportJob,
  AiImportJobResponse,
  AiImportPreviewResponse,
  AiImportProgress,
  AiImportStage,
  AiImportTarget,
  AiPreviewPayload,
  AiPreviewPayloadOneOf,
  AiPreviewPayloadOneOf1,
  AiPreviewPayloadOneOf2,
  AiProviderInfo,
  AppearanceOutfitView,
  AppliedEpisode,
  ApplyAiImportRequest,
  ApplyAiImportResponse,
  ApplyEpisodeGroupRequest,
  ApplyMapping,
  ApplyMappingDecision,
  ApplyMappingDecisionOneOf,
  ApplyMappingDecisionOneOfUpdate,
  ApplyShootingDayRequest,
  AssignCharacterRequest,
  AuditEntry,
  BlockView,
  CharacterAppearanceView,
  CharacterCategory,
  CharacterMeasurements,
  CharacterView,
  CheckpointProgress,
  ContactInfo,
  CostBreakdown,
  CostDisplayPreference,
  CostStatus,
  CostumeCategoryView,
  CreateAiConfigRequest,
  CreateBlockRequest,
  CreateCharacterRequest,
  CreateCostumeCategoryRequest,
  CreateCredentialRequest,
  CreateEpisodeRequest,
  CreateOutfitRequest,
  CreateOutfitVariantRequest,
  CreatePieceRequest,
  CreateSceneRequest,
  CreateSeasonRequest,
  CreateShootingDayRequest,
  CredentialBindingState,
  Currency,
  DeadLetterEntry,
  DecisionOutcome,
  DecisionRubric,
  DecisionTelemetry,
  DispoRow,
  DocumentKind,
  DraftCharacter,
  DraftEpisode,
  DraftOutfit,
  DraftOutfitCandidate,
  DraftOutfitOrigin,
  DraftOutfitProvenance,
  DraftPiece,
  DraftScene,
  DraftShootingDay,
  EnergyCostBreakdown,
  EpisodeTarget,
  EpisodeTargetOneOf,
  EpisodeTargetOneOf1,
  EpisodeView,
  FinishSceneShootRequest,
  GDriveCredentialRequest,
  $GDriveCredentialRequest,
  GDriveCredentialUpdateRequest,
  GrantRoleRequest,
  HealthEntry,
  HealthReport,
  HealthStatus,
  IdVersionResponse,
  ImageCostBreakdown,
  InviteMemberRequest,
  JobStatus,
  JobTelemetrySummary,
  LinkContinuityPhotoRequest,
  LinkShootingDayResponse,
  LlmProvider,
  ManualArchiveJobResult,
  ManualArchiveResponse,
  MembershipStateKind,
  MembershipView,
  MergedPreview,
  MergedScene,
  MetaCreditsEntry,
  MetaCreditsResponse,
  MetaVersionsResponse,
  ModelInfo,
  ModelPricing,
  OutfitContinuityCandidate,
  OutfitContinuitySelection,
  OutfitDecision,
  OutfitPhotoView,
  OutfitPieceView,
  OutfitView,
  PhotoBinding,
  PhotoBindingOneOf,
  PhotoBindingOneOf1,
  PhotoBindingOneOf1Outfit,
  PhotoBindingOneOf2,
  PhotoBindingOneOf2Continuity,
  PhotoBindingOneOfPiece,
  PhotoBytesQuery,
  PhotoVariant,
  PhotoVariantView,
  PhotoView,
  PieceDetailRequest,
  PieceDetailView,
  PiecePhotoView,
  PieceView,
  PlanSceneShootRequest,
  PricingSource,
  ProblemDetails,
  ProjectorHealthSnapshot,
  RenameEpisodeRequest,
  RenameOutfitRequest,
  RenamePieceRequest,
  RenameSeasonRequest,
  ReplanSceneShootRequest,
  RevokeAiConfigRequest,
  Role,
  SceneDetails,
  SceneOutfitBeatView,
  SceneShootStatus,
  SceneShootView,
  SceneSource,
  SceneSourceOneOf,
  SceneSourceOneOfAiExtracted,
  SceneView,
  ScheduleSceneRequest,
  ScriptContext,
  SeasonMembershipDto,
  SeasonView,
  SerializedNote,
  SeriesMembershipDto,
  SetActualOrderRequest,
  SetPieceCategoryRequest,
  SettingsView,
  ShootDayRow,
  ShootingDaySource,
  ShootingDayView,
  ShootingSchedule,
  ShootingScheduleRow,
  SkipSceneShootRequest,
  SollIstDiffRow,
  SollIstReport,
  SourceFormat,
  StartSceneShootRequest,
  TokenCostBreakdown,
  UnappliedOutfit,
  UnappliedOutfitReason,
  Uncertainty,
  UncertaintyAcknowledgement,
  UncertaintyKind,
  UpdateAiConfigRequest,
  UpdateBlockTimeSpanRequest,
  UpdateCharacterCategoryRequest,
  UpdateContactInfoRequest,
  UpdateCostumeCategoryRequest,
  UpdateMeasurementsRequest,
  UpdateNoteRequest,
  UpdateOutfitNotesRequest,
  UpdatePieceDetailRequest,
  UpdatePieceNotesRequest,
  UpdateSceneDetailsRequest,
  UpdateSceneOutfitBeatRequest,
  UpdateShootingDayRequest,
  VariantStatus,
  VersionRequest,
  WrapShootingDayRequest,
])
Serializers serializers = (_$serializers.toBuilder()
      ..addBuilderFactory(
        const FullType(BuiltList, [FullType(ApplyMapping)]),
        () => ListBuilder<ApplyMapping>(),
      )
      ..addBuilderFactory(
        const FullType(BuiltList, [FullType(SerializedNote)]),
        () => ListBuilder<SerializedNote>(),
      )
      ..addBuilderFactory(
        const FullType(BuiltList, [FullType(CharacterView)]),
        () => ListBuilder<CharacterView>(),
      )
      ..addBuilderFactory(
        const FullType(BuiltList, [FullType(PiecePhotoView)]),
        () => ListBuilder<PiecePhotoView>(),
      )
      ..addBuilderFactory(
        const FullType(BuiltList, [FullType(DispoRow)]),
        () => ListBuilder<DispoRow>(),
      )
      ..addBuilderFactory(
        const FullType(BuiltList, [FullType(EpisodeView)]),
        () => ListBuilder<EpisodeView>(),
      )
      ..addBuilderFactory(
        const FullType(BuiltList, [FullType(PieceView)]),
        () => ListBuilder<PieceView>(),
      )
      ..addBuilderFactory(
        const FullType(BuiltList, [FullType(AiImportAttempt)]),
        () => ListBuilder<AiImportAttempt>(),
      )
      ..addBuilderFactory(
        const FullType(BuiltList, [FullType(DraftPiece)]),
        () => ListBuilder<DraftPiece>(),
      )
      ..addBuilderFactory(
        const FullType(BuiltList, [FullType(AiProviderInfo)]),
        () => ListBuilder<AiProviderInfo>(),
      )
      ..addBuilderFactory(
        const FullType(BuiltList, [FullType(OutfitDecision)]),
        () => ListBuilder<OutfitDecision>(),
      )
      ..addBuilderFactory(
        const FullType(BuiltList, [FullType(OutfitContinuitySelection)]),
        () => ListBuilder<OutfitContinuitySelection>(),
      )
      ..addBuilderFactory(
        const FullType(BuiltList, [FullType(SollIstDiffRow)]),
        () => ListBuilder<SollIstDiffRow>(),
      )
      ..addBuilderFactory(
        const FullType(BuiltList, [FullType(DraftScene)]),
        () => ListBuilder<DraftScene>(),
      )
      ..addBuilderFactory(
        const FullType(BuiltList, [FullType(OutfitPhotoView)]),
        () => ListBuilder<OutfitPhotoView>(),
      )
      ..addBuilderFactory(
        const FullType(BuiltList, [FullType(CheckpointProgress)]),
        () => ListBuilder<CheckpointProgress>(),
      )
      ..addBuilderFactory(
        const FullType(BuiltMap, [FullType(String), FullType(double)]),
        () => MapBuilder<String, double>(),
      )
      ..addBuilderFactory(
        const FullType(BuiltList, [FullType(DraftOutfit)]),
        () => ListBuilder<DraftOutfit>(),
      )
      ..addBuilderFactory(
        const FullType(BuiltList, [FullType(AppearanceOutfitView)]),
        () => ListBuilder<AppearanceOutfitView>(),
      )
      ..addBuilderFactory(
        const FullType(BuiltList, [FullType(ShootDayRow)]),
        () => ListBuilder<ShootDayRow>(),
      )
      ..addBuilderFactory(
        const FullType(BuiltList, [FullType(ShootingDayView)]),
        () => ListBuilder<ShootingDayView>(),
      )
      ..addBuilderFactory(
        const FullType(BuiltList, [FullType(SceneShootView)]),
        () => ListBuilder<SceneShootView>(),
      )
      ..addBuilderFactory(
        const FullType(BuiltList, [FullType(SceneOutfitBeatView)]),
        () => ListBuilder<SceneOutfitBeatView>(),
      )
      ..addBuilderFactory(
        const FullType(BuiltList, [FullType(ShootingScheduleRow)]),
        () => ListBuilder<ShootingScheduleRow>(),
      )
      ..addBuilderFactory(
        const FullType(BuiltList, [FullType(PieceDetailView)]),
        () => ListBuilder<PieceDetailView>(),
      )
      ..addBuilderFactory(
        const FullType(BuiltList, [FullType(AuditEntry)]),
        () => ListBuilder<AuditEntry>(),
      )
      ..addBuilderFactory(
        const FullType(BuiltList, [FullType(AiImportJobResponse)]),
        () => ListBuilder<AiImportJobResponse>(),
      )
      ..addBuilderFactory(
        const FullType(BuiltList, [FullType(MergedScene)]),
        () => ListBuilder<MergedScene>(),
      )
      ..addBuilderFactory(
        const FullType(BuiltList, [FullType(UnappliedOutfit)]),
        () => ListBuilder<UnappliedOutfit>(),
      )
      ..addBuilderFactory(
        const FullType(BuiltMap, [FullType(String), FullType(HealthEntry)]),
        () => MapBuilder<String, HealthEntry>(),
      )
      ..addBuilderFactory(
        const FullType(BuiltList, [FullType(BlockView)]),
        () => ListBuilder<BlockView>(),
      )
      ..addBuilderFactory(
        const FullType(BuiltMap, [FullType(String), FullType(String)]),
        () => MapBuilder<String, String>(),
      )
      ..addBuilderFactory(
        const FullType(BuiltList, [FullType(SceneView)]),
        () => ListBuilder<SceneView>(),
      )
      ..addBuilderFactory(
        const FullType(BuiltList, [FullType(SeasonView)]),
        () => ListBuilder<SeasonView>(),
      )
      ..addBuilderFactory(
        const FullType(BuiltList, [FullType(PhotoVariantView)]),
        () => ListBuilder<PhotoVariantView>(),
      )
      ..addBuilderFactory(
        const FullType(BuiltList, [FullType(AiConfigView)]),
        () => ListBuilder<AiConfigView>(),
      )
      ..addBuilderFactory(
        const FullType(BuiltList, [FullType(AggregateSollIstDiffRow)]),
        () => ListBuilder<AggregateSollIstDiffRow>(),
      )
      ..addBuilderFactory(
        const FullType(BuiltList, [FullType(ApplyEpisodeGroupRequest)]),
        () => ListBuilder<ApplyEpisodeGroupRequest>(),
      )
      ..addBuilderFactory(
        const FullType(BuiltList, [FullType(MetaCreditsEntry)]),
        () => ListBuilder<MetaCreditsEntry>(),
      )
      ..addBuilderFactory(
        const FullType(BuiltList, [FullType(ApplyShootingDayRequest)]),
        () => ListBuilder<ApplyShootingDayRequest>(),
      )
      ..addBuilderFactory(
        const FullType(BuiltList, [FullType(DraftOutfitCandidate)]),
        () => ListBuilder<DraftOutfitCandidate>(),
      )
      ..addBuilderFactory(
        const FullType(BuiltList, [FullType(UncertaintyAcknowledgement)]),
        () => ListBuilder<UncertaintyAcknowledgement>(),
      )
      ..addBuilderFactory(
        const FullType(BuiltList, [FullType(DraftCharacter)]),
        () => ListBuilder<DraftCharacter>(),
      )
      ..addBuilderFactory(
        const FullType(BuiltList, [FullType(ModelInfo)]),
        () => ListBuilder<ModelInfo>(),
      )
      ..addBuilderFactory(
        const FullType(BuiltList, [FullType(MembershipView)]),
        () => ListBuilder<MembershipView>(),
      )
      ..addBuilderFactory(
        const FullType(BuiltList, [FullType(CostumeCategoryView)]),
        () => ListBuilder<CostumeCategoryView>(),
      )
      ..addBuilderFactory(
        const FullType(BuiltList, [FullType(AppliedEpisode)]),
        () => ListBuilder<AppliedEpisode>(),
      )
      ..addBuilderFactory(
        const FullType(BuiltList, [FullType(OutfitView)]),
        () => ListBuilder<OutfitView>(),
      )
      ..addBuilderFactory(
        const FullType(BuiltList, [FullType(Uncertainty)]),
        () => ListBuilder<Uncertainty>(),
      )
      ..addBuilderFactory(
        const FullType(BuiltList, [FullType(OutfitPieceView)]),
        () => ListBuilder<OutfitPieceView>(),
      )
      ..addBuilderFactory(
        const FullType(BuiltList, [FullType(ManualArchiveJobResult)]),
        () => ListBuilder<ManualArchiveJobResult>(),
      )
      ..addBuilderFactory(
        const FullType(BuiltList, [FullType(DeadLetterEntry)]),
        () => ListBuilder<DeadLetterEntry>(),
      )
      ..addBuilderFactory(
        const FullType(
            BuiltMap, [FullType(String), FullType.nullable(JsonObject)]),
        () => MapBuilder<String, JsonObject?>(),
      )
      ..addBuilderFactory(
        const FullType(BuiltList, [FullType(CharacterAppearanceView)]),
        () => ListBuilder<CharacterAppearanceView>(),
      )
      ..addBuilderFactory(
        const FullType(BuiltList, [FullType(DocumentKind)]),
        () => ListBuilder<DocumentKind>(),
      )
      ..addBuilderFactory(
        const FullType(BuiltList, [FullType(String)]),
        () => ListBuilder<String>(),
      )
      ..add(GDriveCredentialRequest.serializer)
      ..add(const OneOfSerializer())
      ..add(const AnyOfSerializer())
      ..add(const DateSerializer())
      ..add(Iso8601DateTimeSerializer()))
    .build();

Serializers standardSerializers =
    (serializers.toBuilder()..addPlugin(StandardJsonPlugin())).build();
