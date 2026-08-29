// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'assign_character_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$AssignCharacterRequest extends AssignCharacterRequest {
  @override
  final String characterId;
  @override
  final int version;

  factory _$AssignCharacterRequest(
          [void Function(AssignCharacterRequestBuilder)? updates]) =>
      (AssignCharacterRequestBuilder()..update(updates))._build();

  _$AssignCharacterRequest._({required this.characterId, required this.version})
      : super._();
  @override
  AssignCharacterRequest rebuild(
          void Function(AssignCharacterRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  AssignCharacterRequestBuilder toBuilder() =>
      AssignCharacterRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is AssignCharacterRequest &&
        characterId == other.characterId &&
        version == other.version;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, characterId.hashCode);
    _$hash = $jc(_$hash, version.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'AssignCharacterRequest')
          ..add('characterId', characterId)
          ..add('version', version))
        .toString();
  }
}

class AssignCharacterRequestBuilder
    implements Builder<AssignCharacterRequest, AssignCharacterRequestBuilder> {
  _$AssignCharacterRequest? _$v;

  String? _characterId;
  String? get characterId => _$this._characterId;
  set characterId(String? characterId) => _$this._characterId = characterId;

  int? _version;
  int? get version => _$this._version;
  set version(int? version) => _$this._version = version;

  AssignCharacterRequestBuilder() {
    AssignCharacterRequest._defaults(this);
  }

  AssignCharacterRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _characterId = $v.characterId;
      _version = $v.version;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(AssignCharacterRequest other) {
    _$v = other as _$AssignCharacterRequest;
  }

  @override
  void update(void Function(AssignCharacterRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  AssignCharacterRequest build() => _build();

  _$AssignCharacterRequest _build() {
    final _$result = _$v ??
        _$AssignCharacterRequest._(
          characterId: BuiltValueNullFieldError.checkNotNull(
              characterId, r'AssignCharacterRequest', 'characterId'),
          version: BuiltValueNullFieldError.checkNotNull(
              version, r'AssignCharacterRequest', 'version'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
