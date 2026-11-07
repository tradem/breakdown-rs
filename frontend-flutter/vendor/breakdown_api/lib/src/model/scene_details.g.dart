// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'scene_details.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$SceneDetails extends SceneDetails {
  @override
  final bool isScheduleSet;
  @override
  final String? location;
  @override
  final String? mood;
  @override
  final int? sceneNumber;
  @override
  final double? sceneScore;
  @override
  final String? scriptDay;
  @override
  final String? summary;
  @override
  final double? synopsisScore;

  factory _$SceneDetails([void Function(SceneDetailsBuilder)? updates]) =>
      (SceneDetailsBuilder()..update(updates))._build();

  _$SceneDetails._(
      {required this.isScheduleSet,
      this.location,
      this.mood,
      this.sceneNumber,
      this.sceneScore,
      this.scriptDay,
      this.summary,
      this.synopsisScore})
      : super._();
  @override
  SceneDetails rebuild(void Function(SceneDetailsBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  SceneDetailsBuilder toBuilder() => SceneDetailsBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is SceneDetails &&
        isScheduleSet == other.isScheduleSet &&
        location == other.location &&
        mood == other.mood &&
        sceneNumber == other.sceneNumber &&
        sceneScore == other.sceneScore &&
        scriptDay == other.scriptDay &&
        summary == other.summary &&
        synopsisScore == other.synopsisScore;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, isScheduleSet.hashCode);
    _$hash = $jc(_$hash, location.hashCode);
    _$hash = $jc(_$hash, mood.hashCode);
    _$hash = $jc(_$hash, sceneNumber.hashCode);
    _$hash = $jc(_$hash, sceneScore.hashCode);
    _$hash = $jc(_$hash, scriptDay.hashCode);
    _$hash = $jc(_$hash, summary.hashCode);
    _$hash = $jc(_$hash, synopsisScore.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'SceneDetails')
          ..add('isScheduleSet', isScheduleSet)
          ..add('location', location)
          ..add('mood', mood)
          ..add('sceneNumber', sceneNumber)
          ..add('sceneScore', sceneScore)
          ..add('scriptDay', scriptDay)
          ..add('summary', summary)
          ..add('synopsisScore', synopsisScore))
        .toString();
  }
}

class SceneDetailsBuilder
    implements Builder<SceneDetails, SceneDetailsBuilder> {
  _$SceneDetails? _$v;

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

  double? _sceneScore;
  double? get sceneScore => _$this._sceneScore;
  set sceneScore(double? sceneScore) => _$this._sceneScore = sceneScore;

  String? _scriptDay;
  String? get scriptDay => _$this._scriptDay;
  set scriptDay(String? scriptDay) => _$this._scriptDay = scriptDay;

  String? _summary;
  String? get summary => _$this._summary;
  set summary(String? summary) => _$this._summary = summary;

  double? _synopsisScore;
  double? get synopsisScore => _$this._synopsisScore;
  set synopsisScore(double? synopsisScore) =>
      _$this._synopsisScore = synopsisScore;

  SceneDetailsBuilder() {
    SceneDetails._defaults(this);
  }

  SceneDetailsBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _isScheduleSet = $v.isScheduleSet;
      _location = $v.location;
      _mood = $v.mood;
      _sceneNumber = $v.sceneNumber;
      _sceneScore = $v.sceneScore;
      _scriptDay = $v.scriptDay;
      _summary = $v.summary;
      _synopsisScore = $v.synopsisScore;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(SceneDetails other) {
    _$v = other as _$SceneDetails;
  }

  @override
  void update(void Function(SceneDetailsBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  SceneDetails build() => _build();

  _$SceneDetails _build() {
    final _$result = _$v ??
        _$SceneDetails._(
          isScheduleSet: BuiltValueNullFieldError.checkNotNull(
              isScheduleSet, r'SceneDetails', 'isScheduleSet'),
          location: location,
          mood: mood,
          sceneNumber: sceneNumber,
          sceneScore: sceneScore,
          scriptDay: scriptDay,
          summary: summary,
          synopsisScore: synopsisScore,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
