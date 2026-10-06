// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'add_costume_to_season_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$AddCostumeToSeasonRequest extends AddCostumeToSeasonRequest {
  @override
  final String seasonId;
  @override
  final int version;

  factory _$AddCostumeToSeasonRequest(
          [void Function(AddCostumeToSeasonRequestBuilder)? updates]) =>
      (AddCostumeToSeasonRequestBuilder()..update(updates))._build();

  _$AddCostumeToSeasonRequest._({required this.seasonId, required this.version})
      : super._();
  @override
  AddCostumeToSeasonRequest rebuild(
          void Function(AddCostumeToSeasonRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  AddCostumeToSeasonRequestBuilder toBuilder() =>
      AddCostumeToSeasonRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is AddCostumeToSeasonRequest &&
        seasonId == other.seasonId &&
        version == other.version;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, seasonId.hashCode);
    _$hash = $jc(_$hash, version.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'AddCostumeToSeasonRequest')
          ..add('seasonId', seasonId)
          ..add('version', version))
        .toString();
  }
}

class AddCostumeToSeasonRequestBuilder
    implements
        Builder<AddCostumeToSeasonRequest, AddCostumeToSeasonRequestBuilder> {
  _$AddCostumeToSeasonRequest? _$v;

  String? _seasonId;
  String? get seasonId => _$this._seasonId;
  set seasonId(String? seasonId) => _$this._seasonId = seasonId;

  int? _version;
  int? get version => _$this._version;
  set version(int? version) => _$this._version = version;

  AddCostumeToSeasonRequestBuilder() {
    AddCostumeToSeasonRequest._defaults(this);
  }

  AddCostumeToSeasonRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _seasonId = $v.seasonId;
      _version = $v.version;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(AddCostumeToSeasonRequest other) {
    _$v = other as _$AddCostumeToSeasonRequest;
  }

  @override
  void update(void Function(AddCostumeToSeasonRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  AddCostumeToSeasonRequest build() => _build();

  _$AddCostumeToSeasonRequest _build() {
    final _$result = _$v ??
        _$AddCostumeToSeasonRequest._(
          seasonId: BuiltValueNullFieldError.checkNotNull(
              seasonId, r'AddCostumeToSeasonRequest', 'seasonId'),
          version: BuiltValueNullFieldError.checkNotNull(
              version, r'AddCostumeToSeasonRequest', 'version'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
