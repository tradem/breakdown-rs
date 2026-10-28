// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'apply_ai_import_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ApplyAiImportRequest extends ApplyAiImportRequest {
  @override
  final bool acceptAsIs;
  @override
  final BuiltList<OutfitContinuitySelection>? continuitySelections;
  @override
  final int editDistance;
  @override
  final BuiltList<ApplyEpisodeGroupRequest>? episodeGroups;
  @override
  final String episodeId;
  @override
  final BuiltList<ApplyMapping> mappings;
  @override
  final String? projectId;
  @override
  final BuiltList<ApplyShootingDayRequest>? shootingDays;
  @override
  final BuiltList<UncertaintyAcknowledgement>? uncertaintyAcknowledgements;

  factory _$ApplyAiImportRequest(
          [void Function(ApplyAiImportRequestBuilder)? updates]) =>
      (ApplyAiImportRequestBuilder()..update(updates))._build();

  _$ApplyAiImportRequest._(
      {required this.acceptAsIs,
      this.continuitySelections,
      required this.editDistance,
      this.episodeGroups,
      required this.episodeId,
      required this.mappings,
      this.projectId,
      this.shootingDays,
      this.uncertaintyAcknowledgements})
      : super._();
  @override
  ApplyAiImportRequest rebuild(
          void Function(ApplyAiImportRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ApplyAiImportRequestBuilder toBuilder() =>
      ApplyAiImportRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ApplyAiImportRequest &&
        acceptAsIs == other.acceptAsIs &&
        continuitySelections == other.continuitySelections &&
        editDistance == other.editDistance &&
        episodeGroups == other.episodeGroups &&
        episodeId == other.episodeId &&
        mappings == other.mappings &&
        projectId == other.projectId &&
        shootingDays == other.shootingDays &&
        uncertaintyAcknowledgements == other.uncertaintyAcknowledgements;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, acceptAsIs.hashCode);
    _$hash = $jc(_$hash, continuitySelections.hashCode);
    _$hash = $jc(_$hash, editDistance.hashCode);
    _$hash = $jc(_$hash, episodeGroups.hashCode);
    _$hash = $jc(_$hash, episodeId.hashCode);
    _$hash = $jc(_$hash, mappings.hashCode);
    _$hash = $jc(_$hash, projectId.hashCode);
    _$hash = $jc(_$hash, shootingDays.hashCode);
    _$hash = $jc(_$hash, uncertaintyAcknowledgements.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'ApplyAiImportRequest')
          ..add('acceptAsIs', acceptAsIs)
          ..add('continuitySelections', continuitySelections)
          ..add('editDistance', editDistance)
          ..add('episodeGroups', episodeGroups)
          ..add('episodeId', episodeId)
          ..add('mappings', mappings)
          ..add('projectId', projectId)
          ..add('shootingDays', shootingDays)
          ..add('uncertaintyAcknowledgements', uncertaintyAcknowledgements))
        .toString();
  }
}

class ApplyAiImportRequestBuilder
    implements Builder<ApplyAiImportRequest, ApplyAiImportRequestBuilder> {
  _$ApplyAiImportRequest? _$v;

  bool? _acceptAsIs;
  bool? get acceptAsIs => _$this._acceptAsIs;
  set acceptAsIs(bool? acceptAsIs) => _$this._acceptAsIs = acceptAsIs;

  ListBuilder<OutfitContinuitySelection>? _continuitySelections;
  ListBuilder<OutfitContinuitySelection> get continuitySelections =>
      _$this._continuitySelections ??= ListBuilder<OutfitContinuitySelection>();
  set continuitySelections(
          ListBuilder<OutfitContinuitySelection>? continuitySelections) =>
      _$this._continuitySelections = continuitySelections;

  int? _editDistance;
  int? get editDistance => _$this._editDistance;
  set editDistance(int? editDistance) => _$this._editDistance = editDistance;

  ListBuilder<ApplyEpisodeGroupRequest>? _episodeGroups;
  ListBuilder<ApplyEpisodeGroupRequest> get episodeGroups =>
      _$this._episodeGroups ??= ListBuilder<ApplyEpisodeGroupRequest>();
  set episodeGroups(ListBuilder<ApplyEpisodeGroupRequest>? episodeGroups) =>
      _$this._episodeGroups = episodeGroups;

  String? _episodeId;
  String? get episodeId => _$this._episodeId;
  set episodeId(String? episodeId) => _$this._episodeId = episodeId;

  ListBuilder<ApplyMapping>? _mappings;
  ListBuilder<ApplyMapping> get mappings =>
      _$this._mappings ??= ListBuilder<ApplyMapping>();
  set mappings(ListBuilder<ApplyMapping>? mappings) =>
      _$this._mappings = mappings;

  String? _projectId;
  String? get projectId => _$this._projectId;
  set projectId(String? projectId) => _$this._projectId = projectId;

  ListBuilder<ApplyShootingDayRequest>? _shootingDays;
  ListBuilder<ApplyShootingDayRequest> get shootingDays =>
      _$this._shootingDays ??= ListBuilder<ApplyShootingDayRequest>();
  set shootingDays(ListBuilder<ApplyShootingDayRequest>? shootingDays) =>
      _$this._shootingDays = shootingDays;

  ListBuilder<UncertaintyAcknowledgement>? _uncertaintyAcknowledgements;
  ListBuilder<UncertaintyAcknowledgement> get uncertaintyAcknowledgements =>
      _$this._uncertaintyAcknowledgements ??=
          ListBuilder<UncertaintyAcknowledgement>();
  set uncertaintyAcknowledgements(
          ListBuilder<UncertaintyAcknowledgement>?
              uncertaintyAcknowledgements) =>
      _$this._uncertaintyAcknowledgements = uncertaintyAcknowledgements;

  ApplyAiImportRequestBuilder() {
    ApplyAiImportRequest._defaults(this);
  }

  ApplyAiImportRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _acceptAsIs = $v.acceptAsIs;
      _continuitySelections = $v.continuitySelections?.toBuilder();
      _editDistance = $v.editDistance;
      _episodeGroups = $v.episodeGroups?.toBuilder();
      _episodeId = $v.episodeId;
      _mappings = $v.mappings.toBuilder();
      _projectId = $v.projectId;
      _shootingDays = $v.shootingDays?.toBuilder();
      _uncertaintyAcknowledgements =
          $v.uncertaintyAcknowledgements?.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ApplyAiImportRequest other) {
    _$v = other as _$ApplyAiImportRequest;
  }

  @override
  void update(void Function(ApplyAiImportRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ApplyAiImportRequest build() => _build();

  _$ApplyAiImportRequest _build() {
    _$ApplyAiImportRequest _$result;
    try {
      _$result = _$v ??
          _$ApplyAiImportRequest._(
            acceptAsIs: BuiltValueNullFieldError.checkNotNull(
                acceptAsIs, r'ApplyAiImportRequest', 'acceptAsIs'),
            continuitySelections: _continuitySelections?.build(),
            editDistance: BuiltValueNullFieldError.checkNotNull(
                editDistance, r'ApplyAiImportRequest', 'editDistance'),
            episodeGroups: _episodeGroups?.build(),
            episodeId: BuiltValueNullFieldError.checkNotNull(
                episodeId, r'ApplyAiImportRequest', 'episodeId'),
            mappings: mappings.build(),
            projectId: projectId,
            shootingDays: _shootingDays?.build(),
            uncertaintyAcknowledgements: _uncertaintyAcknowledgements?.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'continuitySelections';
        _continuitySelections?.build();

        _$failedField = 'episodeGroups';
        _episodeGroups?.build();

        _$failedField = 'mappings';
        mappings.build();

        _$failedField = 'shootingDays';
        _shootingDays?.build();
        _$failedField = 'uncertaintyAcknowledgements';
        _uncertaintyAcknowledgements?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'ApplyAiImportRequest', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
