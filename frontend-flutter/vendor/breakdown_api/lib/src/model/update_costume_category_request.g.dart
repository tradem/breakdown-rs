// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'update_costume_category_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$UpdateCostumeCategoryRequest extends UpdateCostumeCategoryRequest {
  @override
  final String? name;
  @override
  final String? orderKey;
  @override
  final int version;

  factory _$UpdateCostumeCategoryRequest(
          [void Function(UpdateCostumeCategoryRequestBuilder)? updates]) =>
      (UpdateCostumeCategoryRequestBuilder()..update(updates))._build();

  _$UpdateCostumeCategoryRequest._(
      {this.name, this.orderKey, required this.version})
      : super._();
  @override
  UpdateCostumeCategoryRequest rebuild(
          void Function(UpdateCostumeCategoryRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  UpdateCostumeCategoryRequestBuilder toBuilder() =>
      UpdateCostumeCategoryRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is UpdateCostumeCategoryRequest &&
        name == other.name &&
        orderKey == other.orderKey &&
        version == other.version;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, name.hashCode);
    _$hash = $jc(_$hash, orderKey.hashCode);
    _$hash = $jc(_$hash, version.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'UpdateCostumeCategoryRequest')
          ..add('name', name)
          ..add('orderKey', orderKey)
          ..add('version', version))
        .toString();
  }
}

class UpdateCostumeCategoryRequestBuilder
    implements
        Builder<UpdateCostumeCategoryRequest,
            UpdateCostumeCategoryRequestBuilder> {
  _$UpdateCostumeCategoryRequest? _$v;

  String? _name;
  String? get name => _$this._name;
  set name(String? name) => _$this._name = name;

  String? _orderKey;
  String? get orderKey => _$this._orderKey;
  set orderKey(String? orderKey) => _$this._orderKey = orderKey;

  int? _version;
  int? get version => _$this._version;
  set version(int? version) => _$this._version = version;

  UpdateCostumeCategoryRequestBuilder() {
    UpdateCostumeCategoryRequest._defaults(this);
  }

  UpdateCostumeCategoryRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _name = $v.name;
      _orderKey = $v.orderKey;
      _version = $v.version;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(UpdateCostumeCategoryRequest other) {
    _$v = other as _$UpdateCostumeCategoryRequest;
  }

  @override
  void update(void Function(UpdateCostumeCategoryRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  UpdateCostumeCategoryRequest build() => _build();

  _$UpdateCostumeCategoryRequest _build() {
    final _$result = _$v ??
        _$UpdateCostumeCategoryRequest._(
          name: name,
          orderKey: orderKey,
          version: BuiltValueNullFieldError.checkNotNull(
              version, r'UpdateCostumeCategoryRequest', 'version'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
