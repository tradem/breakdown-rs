// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'set_actual_order_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$SetActualOrderRequest extends SetActualOrderRequest {
  @override
  final String actualOrder;
  @override
  final int version;

  factory _$SetActualOrderRequest(
          [void Function(SetActualOrderRequestBuilder)? updates]) =>
      (SetActualOrderRequestBuilder()..update(updates))._build();

  _$SetActualOrderRequest._({required this.actualOrder, required this.version})
      : super._();
  @override
  SetActualOrderRequest rebuild(
          void Function(SetActualOrderRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  SetActualOrderRequestBuilder toBuilder() =>
      SetActualOrderRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is SetActualOrderRequest &&
        actualOrder == other.actualOrder &&
        version == other.version;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, actualOrder.hashCode);
    _$hash = $jc(_$hash, version.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'SetActualOrderRequest')
          ..add('actualOrder', actualOrder)
          ..add('version', version))
        .toString();
  }
}

class SetActualOrderRequestBuilder
    implements Builder<SetActualOrderRequest, SetActualOrderRequestBuilder> {
  _$SetActualOrderRequest? _$v;

  String? _actualOrder;
  String? get actualOrder => _$this._actualOrder;
  set actualOrder(String? actualOrder) => _$this._actualOrder = actualOrder;

  int? _version;
  int? get version => _$this._version;
  set version(int? version) => _$this._version = version;

  SetActualOrderRequestBuilder() {
    SetActualOrderRequest._defaults(this);
  }

  SetActualOrderRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _actualOrder = $v.actualOrder;
      _version = $v.version;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(SetActualOrderRequest other) {
    _$v = other as _$SetActualOrderRequest;
  }

  @override
  void update(void Function(SetActualOrderRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  SetActualOrderRequest build() => _build();

  _$SetActualOrderRequest _build() {
    final _$result = _$v ??
        _$SetActualOrderRequest._(
          actualOrder: BuiltValueNullFieldError.checkNotNull(
              actualOrder, r'SetActualOrderRequest', 'actualOrder'),
          version: BuiltValueNullFieldError.checkNotNull(
              version, r'SetActualOrderRequest', 'version'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
