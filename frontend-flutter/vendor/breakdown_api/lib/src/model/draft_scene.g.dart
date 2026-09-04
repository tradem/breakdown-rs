// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'draft_scene.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$DraftScene extends DraftScene {
  @override
  final BuiltList<String> characters;
  @override
  final String draftRef;
  @override
  final String? location;
  @override
  final String? mood;
  @override
  final int? sceneNumber;
  @override
  final String? scriptDay;
  @override
  final String? summary;

  factory _$DraftScene([void Function(DraftSceneBuilder)? updates]) =>
      (DraftSceneBuilder()..update(updates))._build();

  _$DraftScene._(
      {required this.characters,
      required this.draftRef,
      this.location,
      this.mood,
      this.sceneNumber,
      this.scriptDay,
      this.summary})
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
        draftRef == other.draftRef &&
        location == other.location &&
        mood == other.mood &&
        sceneNumber == other.sceneNumber &&
        scriptDay == other.scriptDay &&
        summary == other.summary;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, characters.hashCode);
    _$hash = $jc(_$hash, draftRef.hashCode);
    _$hash = $jc(_$hash, location.hashCode);
    _$hash = $jc(_$hash, mood.hashCode);
    _$hash = $jc(_$hash, sceneNumber.hashCode);
    _$hash = $jc(_$hash, scriptDay.hashCode);
    _$hash = $jc(_$hash, summary.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'DraftScene')
          ..add('characters', characters)
          ..add('draftRef', draftRef)
          ..add('location', location)
          ..add('mood', mood)
          ..add('sceneNumber', sceneNumber)
          ..add('scriptDay', scriptDay)
          ..add('summary', summary))
        .toString();
  }
}

class DraftSceneBuilder implements Builder<DraftScene, DraftSceneBuilder> {
  _$DraftScene? _$v;

  ListBuilder<String>? _characters;
  ListBuilder<String> get characters =>
      _$this._characters ??= ListBuilder<String>();
  set characters(ListBuilder<String>? characters) =>
      _$this._characters = characters;

  String? _draftRef;
  String? get draftRef => _$this._draftRef;
  set draftRef(String? draftRef) => _$this._draftRef = draftRef;

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

  String? _summary;
  String? get summary => _$this._summary;
  set summary(String? summary) => _$this._summary = summary;

  DraftSceneBuilder() {
    DraftScene._defaults(this);
  }

  DraftSceneBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _characters = $v.characters.toBuilder();
      _draftRef = $v.draftRef;
      _location = $v.location;
      _mood = $v.mood;
      _sceneNumber = $v.sceneNumber;
      _scriptDay = $v.scriptDay;
      _summary = $v.summary;
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
            characters: characters.build(),
            draftRef: BuiltValueNullFieldError.checkNotNull(
                draftRef, r'DraftScene', 'draftRef'),
            location: location,
            mood: mood,
            sceneNumber: sceneNumber,
            scriptDay: scriptDay,
            summary: summary,
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'characters';
        characters.build();
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
