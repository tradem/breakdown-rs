// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'create_costume_category_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$CreateCostumeCategoryRequest extends CreateCostumeCategoryRequest {
  @override
  final String name;
  @override
  final String orderKey;
  @override
  final String seasonId;

  factory _$CreateCostumeCategoryRequest(
          [void Function(CreateCostumeCategoryRequestBuilder)? updates]) =>
      (CreateCostumeCategoryRequestBuilder()..update(updates))._build();

  _$CreateCostumeCategoryRequest._(
      {required this.name, required this.orderKey, required this.seasonId})
      : super._();
  @override
  CreateCostumeCategoryRequest rebuild(
          void Function(CreateCostumeCategoryRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  CreateCostumeCategoryRequestBuilder toBuilder() =>
      CreateCostumeCategoryRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is CreateCostumeCategoryRequest &&
        name == other.name &&
        orderKey == other.orderKey &&
        seasonId == other.seasonId;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, name.hashCode);
    _$hash = $jc(_$hash, orderKey.hashCode);
    _$hash = $jc(_$hash, seasonId.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'CreateCostumeCategoryRequest')
          ..add('name', name)
          ..add('orderKey', orderKey)
          ..add('seasonId', seasonId))
        .toString();
  }
}

class CreateCostumeCategoryRequestBuilder
    implements
        Builder<CreateCostumeCategoryRequest,
            CreateCostumeCategoryRequestBuilder> {
  _$CreateCostumeCategoryRequest? _$v;

  String? _name;
  String? get name => _$this._name;
  set name(String? name) => _$this._name = name;

  String? _orderKey;
  String? get orderKey => _$this._orderKey;
  set orderKey(String? orderKey) => _$this._orderKey = orderKey;

  String? _seasonId;
  String? get seasonId => _$this._seasonId;
  set seasonId(String? seasonId) => _$this._seasonId = seasonId;

  CreateCostumeCategoryRequestBuilder() {
    CreateCostumeCategoryRequest._defaults(this);
  }

  CreateCostumeCategoryRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _name = $v.name;
      _orderKey = $v.orderKey;
      _seasonId = $v.seasonId;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(CreateCostumeCategoryRequest other) {
    _$v = other as _$CreateCostumeCategoryRequest;
  }

  @override
  void update(void Function(CreateCostumeCategoryRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  CreateCostumeCategoryRequest build() => _build();

  _$CreateCostumeCategoryRequest _build() {
    final _$result = _$v ??
        _$CreateCostumeCategoryRequest._(
          name: BuiltValueNullFieldError.checkNotNull(
              name, r'CreateCostumeCategoryRequest', 'name'),
          orderKey: BuiltValueNullFieldError.checkNotNull(
              orderKey, r'CreateCostumeCategoryRequest', 'orderKey'),
          seasonId: BuiltValueNullFieldError.checkNotNull(
              seasonId, r'CreateCostumeCategoryRequest', 'seasonId'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
