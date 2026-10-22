// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'draft_scene.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$DraftScene extends DraftScene {
  @override
  final BuiltList<DraftCharacter>? characters;
  @override
  final BuiltList<DraftCostume>? costumes;
  @override
  final String draftRef;
  @override
  final DraftEpisode? episode;
  @override
  final String? location;
  @override
  final String? mood;
  @override
  final int? sceneNumber;
  @override
  final double? sceneScore;
  @override
  final DecisionRubric? scoring;
  @override
  final String? scriptDay;
  @override
  final DraftShootingDay? shootingDay;
  @override
  final String? summary;
  @override
  final double? synopsisScore;

  factory _$DraftScene([void Function(DraftSceneBuilder)? updates]) =>
      (DraftSceneBuilder()..update(updates))._build();

  _$DraftScene._(
      {this.characters,
      this.costumes,
      required this.draftRef,
      this.episode,
      this.location,
      this.mood,
      this.sceneNumber,
      this.sceneScore,
      this.scoring,
      this.scriptDay,
      this.shootingDay,
      this.summary,
      this.synopsisScore})
      : super._();
  @override
  DraftScene rebuild(void Function(DraftSceneBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  DraftSceneBuilder toBuilder() => DraftSceneBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is DraftScene &&
        characters == other.characters &&
        costumes == other.costumes &&
        draftRef == other.draftRef &&
        episode == other.episode &&
        location == other.location &&
        mood == other.mood &&
        sceneNumber == other.sceneNumber &&
        sceneScore == other.sceneScore &&
        scoring == other.scoring &&
        scriptDay == other.scriptDay &&
        shootingDay == other.shootingDay &&
        summary == other.summary &&
        synopsisScore == other.synopsisScore;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, characters.hashCode);
    _$hash = $jc(_$hash, costumes.hashCode);
    _$hash = $jc(_$hash, draftRef.hashCode);
    _$hash = $jc(_$hash, episode.hashCode);
    _$hash = $jc(_$hash, location.hashCode);
    _$hash = $jc(_$hash, mood.hashCode);
    _$hash = $jc(_$hash, sceneNumber.hashCode);
    _$hash = $jc(_$hash, sceneScore.hashCode);
    _$hash = $jc(_$hash, scoring.hashCode);
    _$hash = $jc(_$hash, scriptDay.hashCode);
    _$hash = $jc(_$hash, shootingDay.hashCode);
    _$hash = $jc(_$hash, summary.hashCode);
    _$hash = $jc(_$hash, synopsisScore.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'DraftScene')
          ..add('characters', characters)
          ..add('costumes', costumes)
          ..add('draftRef', draftRef)
          ..add('episode', episode)
          ..add('location', location)
          ..add('mood', mood)
          ..add('sceneNumber', sceneNumber)
          ..add('sceneScore', sceneScore)
          ..add('scoring', scoring)
          ..add('scriptDay', scriptDay)
          ..add('shootingDay', shootingDay)
          ..add('summary', summary)
          ..add('synopsisScore', synopsisScore))
        .toString();
  }
}

class DraftSceneBuilder implements Builder<DraftScene, DraftSceneBuilder> {
  _$DraftScene? _$v;

  ListBuilder<DraftCharacter>? _characters;
  ListBuilder<DraftCharacter> get characters =>
      _$this._characters ??= ListBuilder<DraftCharacter>();
  set characters(ListBuilder<DraftCharacter>? characters) =>
      _$this._characters = characters;

  ListBuilder<DraftCostume>? _costumes;
  ListBuilder<DraftCostume> get costumes =>
      _$this._costumes ??= ListBuilder<DraftCostume>();
  set costumes(ListBuilder<DraftCostume>? costumes) =>
      _$this._costumes = costumes;

  String? _draftRef;
  String? get draftRef => _$this._draftRef;
  set draftRef(String? draftRef) => _$this._draftRef = draftRef;

  DraftEpisodeBuilder? _episode;
  DraftEpisodeBuilder get episode => _$this._episode ??= DraftEpisodeBuilder();
  set episode(DraftEpisodeBuilder? episode) => _$this._episode = episode;

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

  DecisionRubricBuilder? _scoring;
  DecisionRubricBuilder get scoring =>
      _$this._scoring ??= DecisionRubricBuilder();
  set scoring(DecisionRubricBuilder? scoring) => _$this._scoring = scoring;

  String? _scriptDay;
  String? get scriptDay => _$this._scriptDay;
  set scriptDay(String? scriptDay) => _$this._scriptDay = scriptDay;

  DraftShootingDayBuilder? _shootingDay;
  DraftShootingDayBuilder get shootingDay =>
      _$this._shootingDay ??= DraftShootingDayBuilder();
  set shootingDay(DraftShootingDayBuilder? shootingDay) =>
      _$this._shootingDay = shootingDay;

  String? _summary;
  String? get summary => _$this._summary;
  set summary(String? summary) => _$this._summary = summary;

  double? _synopsisScore;
  double? get synopsisScore => _$this._synopsisScore;
  set synopsisScore(double? synopsisScore) =>
      _$this._synopsisScore = synopsisScore;

  DraftSceneBuilder() {
    DraftScene._defaults(this);
  }

  DraftSceneBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _characters = $v.characters?.toBuilder();
      _costumes = $v.costumes?.toBuilder();
      _draftRef = $v.draftRef;
      _episode = $v.episode?.toBuilder();
      _location = $v.location;
      _mood = $v.mood;
      _sceneNumber = $v.sceneNumber;
      _sceneScore = $v.sceneScore;
      _scoring = $v.scoring?.toBuilder();
      _scriptDay = $v.scriptDay;
      _shootingDay = $v.shootingDay?.toBuilder();
      _summary = $v.summary;
      _synopsisScore = $v.synopsisScore;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(DraftScene other) {
    _$v = other as _$DraftScene;
  }

  @override
  void update(void Function(DraftSceneBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  DraftScene build() => _build();

  _$DraftScene _build() {
    _$DraftScene _$result;
    try {
      _$result = _$v ??
          _$DraftScene._(
            characters: _characters?.build(),
            costumes: _costumes?.build(),
            draftRef: BuiltValueNullFieldError.checkNotNull(
                draftRef, r'DraftScene', 'draftRef'),
            episode: _episode?.build(),
            location: location,
            mood: mood,
            sceneNumber: sceneNumber,
            sceneScore: sceneScore,
            scoring: _scoring?.build(),
            scriptDay: scriptDay,
            shootingDay: _shootingDay?.build(),
            summary: summary,
            synopsisScore: synopsisScore,
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'characters';
        _characters?.build();
        _$failedField = 'costumes';
        _costumes?.build();

        _$failedField = 'episode';
        _episode?.build();

        _$failedField = 'scoring';
        _scoring?.build();

        _$failedField = 'shootingDay';
        _shootingDay?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'DraftScene', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
