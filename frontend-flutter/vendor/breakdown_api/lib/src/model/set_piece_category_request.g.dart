// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'set_piece_category_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$SetPieceCategoryRequest extends SetPieceCategoryRequest {
  @override
  final String? categoryId;
  @override
  final int version;

  factory _$SetPieceCategoryRequest(
          [void Function(SetPieceCategoryRequestBuilder)? updates]) =>
      (SetPieceCategoryRequestBuilder()..update(updates))._build();

  _$SetPieceCategoryRequest._({this.categoryId, required this.version})
      : super._();
  @override
  SetPieceCategoryRequest rebuild(
          void Function(SetPieceCategoryRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  SetPieceCategoryRequestBuilder toBuilder() =>
      SetPieceCategoryRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is SetPieceCategoryRequest &&
        categoryId == other.categoryId &&
        version == other.version;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, categoryId.hashCode);
    _$hash = $jc(_$hash, version.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'SetPieceCategoryRequest')
          ..add('categoryId', categoryId)
          ..add('version', version))
        .toString();
  }
}

class SetPieceCategoryRequestBuilder
    implements
        Builder<SetPieceCategoryRequest, SetPieceCategoryRequestBuilder> {
  _$SetPieceCategoryRequest? _$v;

  String? _categoryId;
  String? get categoryId => _$this._categoryId;
  set categoryId(String? categoryId) => _$this._categoryId = categoryId;

  int? _version;
  int? get version => _$this._version;
  set version(int? version) => _$this._version = version;

  SetPieceCategoryRequestBuilder() {
    SetPieceCategoryRequest._defaults(this);
  }

  SetPieceCategoryRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _categoryId = $v.categoryId;
      _version = $v.version;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(SetPieceCategoryRequest other) {
    _$v = other as _$SetPieceCategoryRequest;
  }

  @override
  void update(void Function(SetPieceCategoryRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  SetPieceCategoryRequest build() => _build();

  _$SetPieceCategoryRequest _build() {
    final _$result = _$v ??
        _$SetPieceCategoryRequest._(
          categoryId: categoryId,
          version: BuiltValueNullFieldError.checkNotNull(
              version, r'SetPieceCategoryRequest', 'version'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
