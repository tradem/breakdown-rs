// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'create_costume_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$CreateCostumeRequest extends CreateCostumeRequest {
  @override
  final String? seasonId;

  factory _$CreateCostumeRequest(
          [void Function(CreateCostumeRequestBuilder)? updates]) =>
      (CreateCostumeRequestBuilder()..update(updates))._build();

  _$CreateCostumeRequest._({this.seasonId}) : super._();
  @override
  CreateCostumeRequest rebuild(
          void Function(CreateCostumeRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  CreateCostumeRequestBuilder toBuilder() =>
      CreateCostumeRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is CreateCostumeRequest && seasonId == other.seasonId;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, seasonId.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'CreateCostumeRequest')
          ..add('seasonId', seasonId))
        .toString();
  }
}

class CreateCostumeRequestBuilder
    implements Builder<CreateCostumeRequest, CreateCostumeRequestBuilder> {
  _$CreateCostumeRequest? _$v;

  String? _seasonId;
  String? get seasonId => _$this._seasonId;
  set seasonId(String? seasonId) => _$this._seasonId = seasonId;

  CreateCostumeRequestBuilder() {
    CreateCostumeRequest._defaults(this);
  }

  CreateCostumeRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _seasonId = $v.seasonId;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(CreateCostumeRequest other) {
    _$v = other as _$CreateCostumeRequest;
  }

  @override
  void update(void Function(CreateCostumeRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  CreateCostumeRequest build() => _build();

  _$CreateCostumeRequest _build() {
    final _$result = _$v ??
        _$CreateCostumeRequest._(
          seasonId: seasonId,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
