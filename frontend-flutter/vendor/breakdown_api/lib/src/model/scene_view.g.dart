// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'scene_view.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$SceneView extends SceneView {
  @override
  final BuiltList<String> assignedCharacters;
  @override
  final String episodeId;
  @override
  final String id;
  @override
  final bool isScheduleSet;
  @override
  final String? location;
  @override
  final String? mood;
  @override
  final int? sceneNumber;
  @override
  final String? scriptDay;
  @override
  final BuiltList<String> shootingDayIds;
  @override
  final String? summary;
  @override
  final DateTime updatedAt;
  @override
  final int version;

  factory _$SceneView([void Function(SceneViewBuilder)? updates]) =>
      (SceneViewBuilder()..update(updates))._build();

  _$SceneView._(
      {required this.assignedCharacters,
      required this.episodeId,
      required this.id,
      required this.isScheduleSet,
      this.location,
      this.mood,
      this.sceneNumber,
      this.scriptDay,
      required this.shootingDayIds,
      this.summary,
      required this.updatedAt,
      required this.version})
      : super._();
  @override
  SceneView rebuild(void Function(SceneViewBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  SceneViewBuilder toBuilder() => SceneViewBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is SceneView &&
        assignedCharacters == other.assignedCharacters &&
        episodeId == other.episodeId &&
        id == other.id &&
        isScheduleSet == other.isScheduleSet &&
        location == other.location &&
        mood == other.mood &&
        sceneNumber == other.sceneNumber &&
        scriptDay == other.scriptDay &&
        shootingDayIds == other.shootingDayIds &&
        summary == other.summary &&
        updatedAt == other.updatedAt &&
        version == other.version;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, assignedCharacters.hashCode);
    _$hash = $jc(_$hash, episodeId.hashCode);
    _$hash = $jc(_$hash, id.hashCode);
    _$hash = $jc(_$hash, isScheduleSet.hashCode);
    _$hash = $jc(_$hash, location.hashCode);
    _$hash = $jc(_$hash, mood.hashCode);
    _$hash = $jc(_$hash, sceneNumber.hashCode);
    _$hash = $jc(_$hash, scriptDay.hashCode);
    _$hash = $jc(_$hash, shootingDayIds.hashCode);
    _$hash = $jc(_$hash, summary.hashCode);
    _$hash = $jc(_$hash, updatedAt.hashCode);
    _$hash = $jc(_$hash, version.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'SceneView')
          ..add('assignedCharacters', assignedCharacters)
          ..add('episodeId', episodeId)
          ..add('id', id)
          ..add('isScheduleSet', isScheduleSet)
          ..add('location', location)
          ..add('mood', mood)
          ..add('sceneNumber', sceneNumber)
          ..add('scriptDay', scriptDay)
          ..add('shootingDayIds', shootingDayIds)
          ..add('summary', summary)
          ..add('updatedAt', updatedAt)
          ..add('version', version))
        .toString();
  }
}

class SceneViewBuilder implements Builder<SceneView, SceneViewBuilder> {
  _$SceneView? _$v;

  ListBuilder<String>? _assignedCharacters;
  ListBuilder<String> get assignedCharacters =>
      _$this._assignedCharacters ??= ListBuilder<String>();
  set assignedCharacters(ListBuilder<String>? assignedCharacters) =>
      _$this._assignedCharacters = assignedCharacters;

  String? _episodeId;
  String? get episodeId => _$this._episodeId;
  set episodeId(String? episodeId) => _$this._episodeId = episodeId;

  String? _id;
  String? get id => _$this._id;
  set id(String? id) => _$this._id = id;

  bool? _isScheduleSet;
  bool? get isScheduleSet => _$this._isScheduleSet;
  set isScheduleSet(bool? isScheduleSet) =>
      _$this._isScheduleSet = isScheduleSet;

  String? _location;
  String? get location => _$this._location;
  set location(String? location) => _$this._location = location;

  String? _mood;
  String? get mood => _$this._mood;
  set mood(String? mood) => _$this._mood = mood;

  int? _sceneNumber;
  int? get sceneNumber => _$this._sceneNumber;
  set sceneNumber(int? sceneNumber) => _$this._sceneNumber = sceneNumber;

  String? _scriptDay;
  String? get scriptDay => _$this._scriptDay;
  set scriptDay(String? scriptDay) => _$this._scriptDay = scriptDay;

  ListBuilder<String>? _shootingDayIds;
  ListBuilder<String> get shootingDayIds =>
      _$this._shootingDayIds ??= ListBuilder<String>();
  set shootingDayIds(ListBuilder<String>? shootingDayIds) =>
      _$this._shootingDayIds = shootingDayIds;

  String? _summary;
  String? get summary => _$this._summary;
  set summary(String? summary) => _$this._summary = summary;

  DateTime? _updatedAt;
  DateTime? get updatedAt => _$this._updatedAt;
  set updatedAt(DateTime? updatedAt) => _$this._updatedAt = updatedAt;

  int? _version;
  int? get version => _$this._version;
  set version(int? version) => _$this._version = version;

  SceneViewBuilder() {
    SceneView._defaults(this);
  }

  SceneViewBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _assignedCharacters = $v.assignedCharacters.toBuilder();
      _episodeId = $v.episodeId;
      _id = $v.id;
      _isScheduleSet = $v.isScheduleSet;
      _location = $v.location;
      _mood = $v.mood;
      _sceneNumber = $v.sceneNumber;
      _scriptDay = $v.scriptDay;
      _shootingDayIds = $v.shootingDayIds.toBuilder();
      _summary = $v.summary;
      _updatedAt = $v.updatedAt;
      _version = $v.version;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(SceneView other) {
    _$v = other as _$SceneView;
  }

  @override
  void update(void Function(SceneViewBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  SceneView build() => _build();

  _$SceneView _build() {
    _$SceneView _$result;
    try {
      _$result = _$v ??
          _$SceneView._(
            assignedCharacters: assignedCharacters.build(),
            episodeId: BuiltValueNullFieldError.checkNotNull(
                episodeId, r'SceneView', 'episodeId'),
            id: BuiltValueNullFieldError.checkNotNull(id, r'SceneView', 'id'),
            isScheduleSet: BuiltValueNullFieldError.checkNotNull(
                isScheduleSet, r'SceneView', 'isScheduleSet'),
            location: location,
            mood: mood,
            sceneNumber: sceneNumber,
            scriptDay: scriptDay,
            shootingDayIds: shootingDayIds.build(),
            summary: summary,
            updatedAt: BuiltValueNullFieldError.checkNotNull(
                updatedAt, r'SceneView', 'updatedAt'),
            version: BuiltValueNullFieldError.checkNotNull(
                version, r'SceneView', 'version'),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'assignedCharacters';
        assignedCharacters.build();

        _$failedField = 'shootingDayIds';
        shootingDayIds.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'SceneView', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
