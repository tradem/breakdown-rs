// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'add_scene_costume_beat_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$AddSceneCostumeBeatRequest extends AddSceneCostumeBeatRequest {
  @override
  final String characterId;
  @override
  final String costumeId;
  @override
  final String? note;
  @override
  final int version;

  factory _$AddSceneCostumeBeatRequest(
          [void Function(AddSceneCostumeBeatRequestBuilder)? updates]) =>
      (AddSceneCostumeBeatRequestBuilder()..update(updates))._build();

  _$AddSceneCostumeBeatRequest._(
      {required this.characterId,
      required this.costumeId,
      this.note,
      required this.version})
      : super._();
  @override
  AddSceneCostumeBeatRequest rebuild(
          void Function(AddSceneCostumeBeatRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  AddSceneCostumeBeatRequestBuilder toBuilder() =>
      AddSceneCostumeBeatRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is AddSceneCostumeBeatRequest &&
        characterId == other.characterId &&
        costumeId == other.costumeId &&
        note == other.note &&
        version == other.version;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, characterId.hashCode);
    _$hash = $jc(_$hash, costumeId.hashCode);
    _$hash = $jc(_$hash, note.hashCode);
    _$hash = $jc(_$hash, version.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'AddSceneCostumeBeatRequest')
          ..add('characterId', characterId)
          ..add('costumeId', costumeId)
          ..add('note', note)
          ..add('version', version))
        .toString();
  }
}

class AddSceneCostumeBeatRequestBuilder
    implements
        Builder<AddSceneCostumeBeatRequest, AddSceneCostumeBeatRequestBuilder> {
  _$AddSceneCostumeBeatRequest? _$v;

  String? _characterId;
  String? get characterId => _$this._characterId;
  set characterId(String? characterId) => _$this._characterId = characterId;

  String? _costumeId;
  String? get costumeId => _$this._costumeId;
  set costumeId(String? costumeId) => _$this._costumeId = costumeId;

  String? _note;
  String? get note => _$this._note;
  set note(String? note) => _$this._note = note;

  int? _version;
  int? get version => _$this._version;
  set version(int? version) => _$this._version = version;

  AddSceneCostumeBeatRequestBuilder() {
    AddSceneCostumeBeatRequest._defaults(this);
  }

  AddSceneCostumeBeatRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _characterId = $v.characterId;
      _costumeId = $v.costumeId;
      _note = $v.note;
      _version = $v.version;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(AddSceneCostumeBeatRequest other) {
    _$v = other as _$AddSceneCostumeBeatRequest;
  }

  @override
  void update(void Function(AddSceneCostumeBeatRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  AddSceneCostumeBeatRequest build() => _build();

  _$AddSceneCostumeBeatRequest _build() {
    final _$result = _$v ??
        _$AddSceneCostumeBeatRequest._(
          characterId: BuiltValueNullFieldError.checkNotNull(
              characterId, r'AddSceneCostumeBeatRequest', 'characterId'),
          costumeId: BuiltValueNullFieldError.checkNotNull(
              costumeId, r'AddSceneCostumeBeatRequest', 'costumeId'),
          note: note,
          version: BuiltValueNullFieldError.checkNotNull(
              version, r'AddSceneCostumeBeatRequest', 'version'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
