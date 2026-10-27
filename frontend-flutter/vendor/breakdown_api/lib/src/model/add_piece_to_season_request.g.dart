// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'add_piece_to_season_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$AddPieceToSeasonRequest extends AddPieceToSeasonRequest {
  @override
  final String seasonId;
  @override
  final int version;

  factory _$AddPieceToSeasonRequest(
          [void Function(AddPieceToSeasonRequestBuilder)? updates]) =>
      (AddPieceToSeasonRequestBuilder()..update(updates))._build();

  _$AddPieceToSeasonRequest._({required this.seasonId, required this.version})
      : super._();
  @override
  AddPieceToSeasonRequest rebuild(
          void Function(AddPieceToSeasonRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  AddPieceToSeasonRequestBuilder toBuilder() =>
      AddPieceToSeasonRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is AddPieceToSeasonRequest &&
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
    return (newBuiltValueToStringHelper(r'AddPieceToSeasonRequest')
          ..add('seasonId', seasonId)
          ..add('version', version))
        .toString();
  }
}

class AddPieceToSeasonRequestBuilder
    implements
        Builder<AddPieceToSeasonRequest, AddPieceToSeasonRequestBuilder> {
  _$AddPieceToSeasonRequest? _$v;

  String? _seasonId;
  String? get seasonId => _$this._seasonId;
  set seasonId(String? seasonId) => _$this._seasonId = seasonId;

  int? _version;
  int? get version => _$this._version;
  set version(int? version) => _$this._version = version;

  AddPieceToSeasonRequestBuilder() {
    AddPieceToSeasonRequest._defaults(this);
  }

  AddPieceToSeasonRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _seasonId = $v.seasonId;
      _version = $v.version;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(AddPieceToSeasonRequest other) {
    _$v = other as _$AddPieceToSeasonRequest;
  }

  @override
  void update(void Function(AddPieceToSeasonRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  AddPieceToSeasonRequest build() => _build();

  _$AddPieceToSeasonRequest _build() {
    final _$result = _$v ??
        _$AddPieceToSeasonRequest._(
          seasonId: BuiltValueNullFieldError.checkNotNull(
              seasonId, r'AddPieceToSeasonRequest', 'seasonId'),
          version: BuiltValueNullFieldError.checkNotNull(
              version, r'AddPieceToSeasonRequest', 'version'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
