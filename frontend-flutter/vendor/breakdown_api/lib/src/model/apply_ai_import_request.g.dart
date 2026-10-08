// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'apply_ai_import_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ApplyAiImportRequest extends ApplyAiImportRequest {
  @override
  final bool acceptAsIs;
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

  factory _$ApplyAiImportRequest(
          [void Function(ApplyAiImportRequestBuilder)? updates]) =>
      (ApplyAiImportRequestBuilder()..update(updates))._build();

  _$ApplyAiImportRequest._(
      {required this.acceptAsIs,
      required this.editDistance,
      this.episodeGroups,
      required this.episodeId,
      required this.mappings,
      this.projectId})
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
        editDistance == other.editDistance &&
        episodeGroups == other.episodeGroups &&
        episodeId == other.episodeId &&
        mappings == other.mappings &&
        projectId == other.projectId;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, acceptAsIs.hashCode);
    _$hash = $jc(_$hash, editDistance.hashCode);
    _$hash = $jc(_$hash, episodeGroups.hashCode);
    _$hash = $jc(_$hash, episodeId.hashCode);
    _$hash = $jc(_$hash, mappings.hashCode);
    _$hash = $jc(_$hash, projectId.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'ApplyAiImportRequest')
          ..add('acceptAsIs', acceptAsIs)
          ..add('editDistance', editDistance)
          ..add('episodeGroups', episodeGroups)
          ..add('episodeId', episodeId)
          ..add('mappings', mappings)
          ..add('projectId', projectId))
        .toString();
  }
}

class ApplyAiImportRequestBuilder
    implements Builder<ApplyAiImportRequest, ApplyAiImportRequestBuilder> {
  _$ApplyAiImportRequest? _$v;

  bool? _acceptAsIs;
  bool? get acceptAsIs => _$this._acceptAsIs;
  set acceptAsIs(bool? acceptAsIs) => _$this._acceptAsIs = acceptAsIs;

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

  ApplyAiImportRequestBuilder() {
    ApplyAiImportRequest._defaults(this);
  }

  ApplyAiImportRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _acceptAsIs = $v.acceptAsIs;
      _editDistance = $v.editDistance;
      _episodeGroups = $v.episodeGroups?.toBuilder();
      _episodeId = $v.episodeId;
      _mappings = $v.mappings.toBuilder();
      _projectId = $v.projectId;
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
            editDistance: BuiltValueNullFieldError.checkNotNull(
                editDistance, r'ApplyAiImportRequest', 'editDistance'),
            episodeGroups: _episodeGroups?.build(),
            episodeId: BuiltValueNullFieldError.checkNotNull(
                episodeId, r'ApplyAiImportRequest', 'episodeId'),
            mappings: mappings.build(),
            projectId: projectId,
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'episodeGroups';
        _episodeGroups?.build();

        _$failedField = 'mappings';
        mappings.build();
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
