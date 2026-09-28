// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'set_costume_category_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$SetCostumeCategoryRequest extends SetCostumeCategoryRequest {
  @override
  final String? categoryId;
  @override
  final int version;

  factory _$SetCostumeCategoryRequest(
          [void Function(SetCostumeCategoryRequestBuilder)? updates]) =>
      (SetCostumeCategoryRequestBuilder()..update(updates))._build();

  _$SetCostumeCategoryRequest._({this.categoryId, required this.version})
      : super._();
  @override
  SetCostumeCategoryRequest rebuild(
          void Function(SetCostumeCategoryRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  SetCostumeCategoryRequestBuilder toBuilder() =>
      SetCostumeCategoryRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is SetCostumeCategoryRequest &&
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
    return (newBuiltValueToStringHelper(r'SetCostumeCategoryRequest')
          ..add('categoryId', categoryId)
          ..add('version', version))
        .toString();
  }
}

class SetCostumeCategoryRequestBuilder
    implements
        Builder<SetCostumeCategoryRequest, SetCostumeCategoryRequestBuilder> {
  _$SetCostumeCategoryRequest? _$v;

  String? _categoryId;
  String? get categoryId => _$this._categoryId;
  set categoryId(String? categoryId) => _$this._categoryId = categoryId;

  int? _version;
  int? get version => _$this._version;
  set version(int? version) => _$this._version = version;

  SetCostumeCategoryRequestBuilder() {
    SetCostumeCategoryRequest._defaults(this);
  }

  SetCostumeCategoryRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _categoryId = $v.categoryId;
      _version = $v.version;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(SetCostumeCategoryRequest other) {
    _$v = other as _$SetCostumeCategoryRequest;
  }

  @override
  void update(void Function(SetCostumeCategoryRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  SetCostumeCategoryRequest build() => _build();

  _$SetCostumeCategoryRequest _build() {
    final _$result = _$v ??
        _$SetCostumeCategoryRequest._(
          categoryId: categoryId,
          version: BuiltValueNullFieldError.checkNotNull(
              version, r'SetCostumeCategoryRequest', 'version'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
