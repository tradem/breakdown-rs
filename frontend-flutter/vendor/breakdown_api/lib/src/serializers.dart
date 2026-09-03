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

import 'package:breakdown_api/src/model/add_costume_detail_request.dart';
import 'package:breakdown_api/src/model/add_note_request.dart';
import 'package:breakdown_api/src/model/ai_config_view.dart';
import 'package:breakdown_api/src/model/ai_import_job.dart';
import 'package:breakdown_api/src/model/ai_import_job_response.dart';
import 'package:breakdown_api/src/model/ai_provider_info.dart';
import 'package:breakdown_api/src/model/apply_ai_import_request.dart';
import 'package:breakdown_api/src/model/apply_ai_import_response.dart';
import 'package:breakdown_api/src/model/apply_mapping.dart';
import 'package:breakdown_api/src/model/apply_mapping_decision.dart';
import 'package:breakdown_api/src/model/apply_mapping_decision_one_of.dart';
import 'package:breakdown_api/src/model/apply_mapping_decision_one_of_update.dart';
import 'package:breakdown_api/src/model/assign_character_request.dart';
import 'package:breakdown_api/src/model/assign_costume_request.dart';
import 'package:breakdown_api/src/model/audit_entry.dart';
import 'package:breakdown_api/src/model/block_view.dart';
import 'package:breakdown_api/src/model/character_category.dart';
import 'package:breakdown_api/src/model/character_measurements.dart';
import 'package:breakdown_api/src/model/character_view.dart';
import 'package:breakdown_api/src/model/contact_info.dart';
import 'package:breakdown_api/src/model/costume_category_view.dart';
import 'package:breakdown_api/src/model/costume_detail.dart';
import 'package:breakdown_api/src/model/costume_detail_view.dart';
import 'package:breakdown_api/src/model/costume_photo_view.dart';
import 'package:breakdown_api/src/model/costume_view.dart';
import 'package:breakdown_api/src/model/create_ai_config_request.dart';
import 'package:breakdown_api/src/model/create_block_request.dart';
import 'package:breakdown_api/src/model/create_character_request.dart';
import 'package:breakdown_api/src/model/create_costume_category_request.dart';
import 'package:breakdown_api/src/model/create_credential_request.dart';
import 'package:breakdown_api/src/model/create_episode_request.dart';
import 'package:breakdown_api/src/model/create_scene_request.dart';
import 'package:breakdown_api/src/model/create_season_request.dart';
import 'package:breakdown_api/src/model/create_shooting_day_request.dart';
import 'package:breakdown_api/src/model/credential_binding_state.dart';
import 'package:breakdown_api/src/model/dispo_row.dart';
import 'package:breakdown_api/src/model/document_kind.dart';
import 'package:breakdown_api/src/model/episode_view.dart';
import 'package:breakdown_api/src/model/finish_scene_shoot_request.dart';
import 'package:breakdown_api/src/model/g_drive_credential_request.dart';
import 'package:breakdown_api/src/model/g_drive_credential_update_request.dart';
import 'package:breakdown_api/src/model/grant_role_request.dart';
import 'package:breakdown_api/src/model/id_version_response.dart';
import 'package:breakdown_api/src/model/invite_member_request.dart';
import 'package:breakdown_api/src/model/job_status.dart';
import 'package:breakdown_api/src/model/link_continuity_photo_request.dart';
import 'package:breakdown_api/src/model/llm_provider.dart';
import 'package:breakdown_api/src/model/manual_archive_job_result.dart';
import 'package:breakdown_api/src/model/manual_archive_response.dart';
import 'package:breakdown_api/src/model/membership_state_kind.dart';
import 'package:breakdown_api/src/model/membership_view.dart';
import 'package:breakdown_api/src/model/model_info.dart';
import 'package:breakdown_api/src/model/photo_binding.dart';
import 'package:breakdown_api/src/model/photo_binding_one_of.dart';
import 'package:breakdown_api/src/model/photo_binding_one_of1.dart';
import 'package:breakdown_api/src/model/photo_binding_one_of1_continuity.dart';
import 'package:breakdown_api/src/model/photo_binding_one_of_costume.dart';
import 'package:breakdown_api/src/model/photo_bytes_query.dart';
import 'package:breakdown_api/src/model/photo_variant.dart';
import 'package:breakdown_api/src/model/photo_variant_view.dart';
import 'package:breakdown_api/src/model/photo_view.dart';
import 'package:breakdown_api/src/model/plan_scene_shoot_request.dart';
import 'package:breakdown_api/src/model/problem_details.dart';
import 'package:breakdown_api/src/model/rename_episode_request.dart';
import 'package:breakdown_api/src/model/rename_season_request.dart';
import 'package:breakdown_api/src/model/replan_scene_shoot_request.dart';
import 'package:breakdown_api/src/model/revoke_ai_config_request.dart';
import 'package:breakdown_api/src/model/role.dart';
import 'package:breakdown_api/src/model/scene_details.dart';
import 'package:breakdown_api/src/model/scene_shoot_status.dart';
import 'package:breakdown_api/src/model/scene_shoot_view.dart';
import 'package:breakdown_api/src/model/scene_view.dart';
import 'package:breakdown_api/src/model/schedule_scene_request.dart';
import 'package:breakdown_api/src/model/season_membership_dto.dart';
import 'package:breakdown_api/src/model/season_view.dart';
import 'package:breakdown_api/src/model/serialized_note.dart';
import 'package:breakdown_api/src/model/set_actual_order_request.dart';
import 'package:breakdown_api/src/model/settings_view.dart';
import 'package:breakdown_api/src/model/shoot_day_row.dart';
import 'package:breakdown_api/src/model/shooting_day_source.dart';
import 'package:breakdown_api/src/model/shooting_day_source_one_of.dart';
import 'package:breakdown_api/src/model/shooting_day_source_one_of_ai_extracted.dart';
import 'package:breakdown_api/src/model/shooting_day_view.dart';
import 'package:breakdown_api/src/model/skip_scene_shoot_request.dart';
import 'package:breakdown_api/src/model/soll_ist_diff_row.dart';
import 'package:breakdown_api/src/model/soll_ist_report.dart';
import 'package:breakdown_api/src/model/source_format.dart';
import 'package:breakdown_api/src/model/start_scene_shoot_request.dart';
import 'package:breakdown_api/src/model/update_ai_config_request.dart';
import 'package:breakdown_api/src/model/update_block_time_span_request.dart';
import 'package:breakdown_api/src/model/update_contact_info_request.dart';
import 'package:breakdown_api/src/model/update_costume_category_request.dart';
import 'package:breakdown_api/src/model/update_costume_notes_request.dart';
import 'package:breakdown_api/src/model/update_measurements_request.dart';
import 'package:breakdown_api/src/model/update_note_request.dart';
import 'package:breakdown_api/src/model/update_scene_details_request.dart';
import 'package:breakdown_api/src/model/update_shooting_day_request.dart';
import 'package:breakdown_api/src/model/variant_status.dart';
import 'package:breakdown_api/src/model/version_request.dart';
import 'package:breakdown_api/src/model/wrap_shooting_day_request.dart';

part 'serializers.g.dart';

@SerializersFor([
  AddCostumeDetailRequest,
  AddNoteRequest,
  AiConfigView,
  AiImportJob,
  AiImportJobResponse,
  AiProviderInfo,
  ApplyAiImportRequest,
  ApplyAiImportResponse,
  ApplyMapping,
  ApplyMappingDecision,
  ApplyMappingDecisionOneOf,
  ApplyMappingDecisionOneOfUpdate,
  AssignCharacterRequest,
  AssignCostumeRequest,
  AuditEntry,
  BlockView,
  CharacterCategory,
  CharacterMeasurements,
  CharacterView,
  ContactInfo,
  CostumeCategoryView,
  CostumeDetail,
  CostumeDetailView,
  CostumePhotoView,
  CostumeView,
  CreateAiConfigRequest,
  CreateBlockRequest,
  CreateCharacterRequest,
  CreateCostumeCategoryRequest,
  CreateCredentialRequest,
  CreateEpisodeRequest,
  CreateSceneRequest,
  CreateSeasonRequest,
  CreateShootingDayRequest,
  CredentialBindingState,
  DispoRow,
  DocumentKind,
  EpisodeView,
  FinishSceneShootRequest,
  GDriveCredentialRequest,
  $GDriveCredentialRequest,
  GDriveCredentialUpdateRequest,
  GrantRoleRequest,
  IdVersionResponse,
  InviteMemberRequest,
  JobStatus,
  LinkContinuityPhotoRequest,
  LlmProvider,
  ManualArchiveJobResult,
  ManualArchiveResponse,
  MembershipStateKind,
  MembershipView,
  ModelInfo,
  PhotoBinding,
  PhotoBindingOneOf,
  PhotoBindingOneOf1,
  PhotoBindingOneOf1Continuity,
  PhotoBindingOneOfCostume,
  PhotoBytesQuery,
  PhotoVariant,
  PhotoVariantView,
  PhotoView,
  PlanSceneShootRequest,
  ProblemDetails,
  RenameEpisodeRequest,
  RenameSeasonRequest,
  ReplanSceneShootRequest,
  RevokeAiConfigRequest,
  Role,
  SceneDetails,
  SceneShootStatus,
  SceneShootView,
  SceneView,
  ScheduleSceneRequest,
  SeasonMembershipDto,
  SeasonView,
  SerializedNote,
  SetActualOrderRequest,
  SettingsView,
  ShootDayRow,
  ShootingDaySource,
  ShootingDaySourceOneOf,
  ShootingDaySourceOneOfAiExtracted,
  ShootingDayView,
  SkipSceneShootRequest,
  SollIstDiffRow,
  SollIstReport,
  SourceFormat,
  StartSceneShootRequest,
  UpdateAiConfigRequest,
  UpdateBlockTimeSpanRequest,
  UpdateContactInfoRequest,
  UpdateCostumeCategoryRequest,
  UpdateCostumeNotesRequest,
  UpdateMeasurementsRequest,
  UpdateNoteRequest,
  UpdateSceneDetailsRequest,
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
        const FullType(BuiltList, [FullType(CostumeDetailView)]),
        () => ListBuilder<CostumeDetailView>(),
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
        const FullType(BuiltList, [FullType(SerializedNote)]),
        () => ListBuilder<SerializedNote>(),
      )
      ..addBuilderFactory(
        const FullType(BuiltList, [FullType(CharacterView)]),
        () => ListBuilder<CharacterView>(),
      )
      ..addBuilderFactory(
        const FullType(BuiltList, [FullType(PhotoVariantView)]),
        () => ListBuilder<PhotoVariantView>(),
      )
      ..addBuilderFactory(
        const FullType(BuiltList, [FullType(CostumePhotoView)]),
        () => ListBuilder<CostumePhotoView>(),
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
        const FullType(BuiltList, [FullType(AiProviderInfo)]),
        () => ListBuilder<AiProviderInfo>(),
      )
      ..addBuilderFactory(
        const FullType(BuiltList, [FullType(SollIstDiffRow)]),
        () => ListBuilder<SollIstDiffRow>(),
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
        const FullType(BuiltList, [FullType(AuditEntry)]),
        () => ListBuilder<AuditEntry>(),
      )
      ..addBuilderFactory(
        const FullType(BuiltList, [FullType(ManualArchiveJobResult)]),
        () => ListBuilder<ManualArchiveJobResult>(),
      )
      ..addBuilderFactory(
        const FullType(
            BuiltMap, [FullType(String), FullType.nullable(JsonObject)]),
        () => MapBuilder<String, JsonObject?>(),
      )
      ..addBuilderFactory(
        const FullType(BuiltList, [FullType(CostumeView)]),
        () => ListBuilder<CostumeView>(),
      )
      ..addBuilderFactory(
        const FullType(BuiltList, [FullType(BlockView)]),
        () => ListBuilder<BlockView>(),
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
