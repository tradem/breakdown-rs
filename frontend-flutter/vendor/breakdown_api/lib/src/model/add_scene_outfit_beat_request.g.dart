// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'add_scene_outfit_beat_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$AddSceneOutfitBeatRequest extends AddSceneOutfitBeatRequest {
  @override
  final String characterId;
  @override
  final String? note;
  @override
  final String outfitId;
  @override
  final int version;

  factory _$AddSceneOutfitBeatRequest(
          [void Function(AddSceneOutfitBeatRequestBuilder)? updates]) =>
      (AddSceneOutfitBeatRequestBuilder()..update(updates))._build();

  _$AddSceneOutfitBeatRequest._(
      {required this.characterId,
      this.note,
      required this.outfitId,
      required this.version})
      : super._();
  @override
  AddSceneOutfitBeatRequest rebuild(
          void Function(AddSceneOutfitBeatRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  AddSceneOutfitBeatRequestBuilder toBuilder() =>
      AddSceneOutfitBeatRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is AddSceneOutfitBeatRequest &&
        characterId == other.characterId &&
        note == other.note &&
        outfitId == other.outfitId &&
        version == other.version;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, characterId.hashCode);
    _$hash = $jc(_$hash, note.hashCode);
    _$hash = $jc(_$hash, outfitId.hashCode);
    _$hash = $jc(_$hash, version.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'AddSceneOutfitBeatRequest')
          ..add('characterId', characterId)
          ..add('note', note)
          ..add('outfitId', outfitId)
          ..add('version', version))
        .toString();
  }
}

class AddSceneOutfitBeatRequestBuilder
    implements
        Builder<AddSceneOutfitBeatRequest, AddSceneOutfitBeatRequestBuilder> {
  _$AddSceneOutfitBeatRequest? _$v;

  String? _characterId;
  String? get characterId => _$this._characterId;
  set characterId(String? characterId) => _$this._characterId = characterId;

  String? _note;
  String? get note => _$this._note;
  set note(String? note) => _$this._note = note;

  String? _outfitId;
  String? get outfitId => _$this._outfitId;
  set outfitId(String? outfitId) => _$this._outfitId = outfitId;

  int? _version;
  int? get version => _$this._version;
  set version(int? version) => _$this._version = version;

  AddSceneOutfitBeatRequestBuilder() {
    AddSceneOutfitBeatRequest._defaults(this);
  }

  AddSceneOutfitBeatRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _characterId = $v.characterId;
      _note = $v.note;
      _outfitId = $v.outfitId;
      _version = $v.version;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(AddSceneOutfitBeatRequest other) {
    _$v = other as _$AddSceneOutfitBeatRequest;
  }

  @override
  void update(void Function(AddSceneOutfitBeatRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  AddSceneOutfitBeatRequest build() => _build();

  _$AddSceneOutfitBeatRequest _build() {
    final _$result = _$v ??
        _$AddSceneOutfitBeatRequest._(
          characterId: BuiltValueNullFieldError.checkNotNull(
              characterId, r'AddSceneOutfitBeatRequest', 'characterId'),
          note: note,
          outfitId: BuiltValueNullFieldError.checkNotNull(
              outfitId, r'AddSceneOutfitBeatRequest', 'outfitId'),
          version: BuiltValueNullFieldError.checkNotNull(
              version, r'AddSceneOutfitBeatRequest', 'version'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
