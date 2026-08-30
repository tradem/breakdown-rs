// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'assign_costume_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$AssignCostumeRequest extends AssignCostumeRequest {
  @override
  final String characterId;
  @override
  final int version;

  factory _$AssignCostumeRequest(
          [void Function(AssignCostumeRequestBuilder)? updates]) =>
      (AssignCostumeRequestBuilder()..update(updates))._build();

  _$AssignCostumeRequest._({required this.characterId, required this.version})
      : super._();
  @override
  AssignCostumeRequest rebuild(
          void Function(AssignCostumeRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  AssignCostumeRequestBuilder toBuilder() =>
      AssignCostumeRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is AssignCostumeRequest &&
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
    return (newBuiltValueToStringHelper(r'AssignCostumeRequest')
          ..add('characterId', characterId)
          ..add('version', version))
        .toString();
  }
}

class AssignCostumeRequestBuilder
    implements Builder<AssignCostumeRequest, AssignCostumeRequestBuilder> {
  _$AssignCostumeRequest? _$v;

  String? _characterId;
  String? get characterId => _$this._characterId;
  set characterId(String? characterId) => _$this._characterId = characterId;

  int? _version;
  int? get version => _$this._version;
  set version(int? version) => _$this._version = version;

  AssignCostumeRequestBuilder() {
    AssignCostumeRequest._defaults(this);
  }

  AssignCostumeRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _characterId = $v.characterId;
      _version = $v.version;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(AssignCostumeRequest other) {
    _$v = other as _$AssignCostumeRequest;
  }

  @override
  void update(void Function(AssignCostumeRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  AssignCostumeRequest build() => _build();

  _$AssignCostumeRequest _build() {
    final _$result = _$v ??
        _$AssignCostumeRequest._(
          characterId: BuiltValueNullFieldError.checkNotNull(
              characterId, r'AssignCostumeRequest', 'characterId'),
          version: BuiltValueNullFieldError.checkNotNull(
              version, r'AssignCostumeRequest', 'version'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
