// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'plan_scene_shoot_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$PlanSceneShootRequest extends PlanSceneShootRequest {
  @override
  final String plannedOrder;

  factory _$PlanSceneShootRequest(
          [void Function(PlanSceneShootRequestBuilder)? updates]) =>
      (PlanSceneShootRequestBuilder()..update(updates))._build();

  _$PlanSceneShootRequest._({required this.plannedOrder}) : super._();
  @override
  PlanSceneShootRequest rebuild(
          void Function(PlanSceneShootRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  PlanSceneShootRequestBuilder toBuilder() =>
      PlanSceneShootRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is PlanSceneShootRequest && plannedOrder == other.plannedOrder;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, plannedOrder.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'PlanSceneShootRequest')
          ..add('plannedOrder', plannedOrder))
        .toString();
  }
}

class PlanSceneShootRequestBuilder
    implements Builder<PlanSceneShootRequest, PlanSceneShootRequestBuilder> {
  _$PlanSceneShootRequest? _$v;

  String? _plannedOrder;
  String? get plannedOrder => _$this._plannedOrder;
  set plannedOrder(String? plannedOrder) => _$this._plannedOrder = plannedOrder;

  PlanSceneShootRequestBuilder() {
    PlanSceneShootRequest._defaults(this);
  }

  PlanSceneShootRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _plannedOrder = $v.plannedOrder;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(PlanSceneShootRequest other) {
    _$v = other as _$PlanSceneShootRequest;
  }

  @override
  void update(void Function(PlanSceneShootRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  PlanSceneShootRequest build() => _build();

  _$PlanSceneShootRequest _build() {
    final _$result = _$v ??
        _$PlanSceneShootRequest._(
          plannedOrder: BuiltValueNullFieldError.checkNotNull(
              plannedOrder, r'PlanSceneShootRequest', 'plannedOrder'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
