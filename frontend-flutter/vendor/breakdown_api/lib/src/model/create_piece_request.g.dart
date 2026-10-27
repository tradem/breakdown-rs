// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'create_piece_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$CreatePieceRequest extends CreatePieceRequest {
  @override
  final String? categoryId;
  @override
  final String name;
  @override
  final String? seasonId;

  factory _$CreatePieceRequest(
          [void Function(CreatePieceRequestBuilder)? updates]) =>
      (CreatePieceRequestBuilder()..update(updates))._build();

  _$CreatePieceRequest._({this.categoryId, required this.name, this.seasonId})
      : super._();
  @override
  CreatePieceRequest rebuild(
          void Function(CreatePieceRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  CreatePieceRequestBuilder toBuilder() =>
      CreatePieceRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is CreatePieceRequest &&
        categoryId == other.categoryId &&
        name == other.name &&
        seasonId == other.seasonId;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, categoryId.hashCode);
    _$hash = $jc(_$hash, name.hashCode);
    _$hash = $jc(_$hash, seasonId.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'CreatePieceRequest')
          ..add('categoryId', categoryId)
          ..add('name', name)
          ..add('seasonId', seasonId))
        .toString();
  }
}

class CreatePieceRequestBuilder
    implements Builder<CreatePieceRequest, CreatePieceRequestBuilder> {
  _$CreatePieceRequest? _$v;

  String? _categoryId;
  String? get categoryId => _$this._categoryId;
  set categoryId(String? categoryId) => _$this._categoryId = categoryId;

  String? _name;
  String? get name => _$this._name;
  set name(String? name) => _$this._name = name;

  String? _seasonId;
  String? get seasonId => _$this._seasonId;
  set seasonId(String? seasonId) => _$this._seasonId = seasonId;

  CreatePieceRequestBuilder() {
    CreatePieceRequest._defaults(this);
  }

  CreatePieceRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _categoryId = $v.categoryId;
      _name = $v.name;
      _seasonId = $v.seasonId;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(CreatePieceRequest other) {
    _$v = other as _$CreatePieceRequest;
  }

  @override
  void update(void Function(CreatePieceRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  CreatePieceRequest build() => _build();

  _$CreatePieceRequest _build() {
    final _$result = _$v ??
        _$CreatePieceRequest._(
          categoryId: categoryId,
          name: BuiltValueNullFieldError.checkNotNull(
              name, r'CreatePieceRequest', 'name'),
          seasonId: seasonId,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
