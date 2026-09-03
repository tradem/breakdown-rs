// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'replan_scene_shoot_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ReplanSceneShootRequest extends ReplanSceneShootRequest {
  @override
  final String plannedOrder;
  @override
  final int version;

  factory _$ReplanSceneShootRequest(
          [void Function(ReplanSceneShootRequestBuilder)? updates]) =>
      (ReplanSceneShootRequestBuilder()..update(updates))._build();

  _$ReplanSceneShootRequest._(
      {required this.plannedOrder, required this.version})
      : super._();
  @override
  ReplanSceneShootRequest rebuild(
          void Function(ReplanSceneShootRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ReplanSceneShootRequestBuilder toBuilder() =>
      ReplanSceneShootRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ReplanSceneShootRequest &&
        plannedOrder == other.plannedOrder &&
        version == other.version;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, plannedOrder.hashCode);
    _$hash = $jc(_$hash, version.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'ReplanSceneShootRequest')
          ..add('plannedOrder', plannedOrder)
          ..add('version', version))
        .toString();
  }
}

class ReplanSceneShootRequestBuilder
    implements
        Builder<ReplanSceneShootRequest, ReplanSceneShootRequestBuilder> {
  _$ReplanSceneShootRequest? _$v;

  String? _plannedOrder;
  String? get plannedOrder => _$this._plannedOrder;
  set plannedOrder(String? plannedOrder) => _$this._plannedOrder = plannedOrder;

  int? _version;
  int? get version => _$this._version;
  set version(int? version) => _$this._version = version;

  ReplanSceneShootRequestBuilder() {
    ReplanSceneShootRequest._defaults(this);
  }

  ReplanSceneShootRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _plannedOrder = $v.plannedOrder;
      _version = $v.version;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ReplanSceneShootRequest other) {
    _$v = other as _$ReplanSceneShootRequest;
  }

  @override
  void update(void Function(ReplanSceneShootRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ReplanSceneShootRequest build() => _build();

  _$ReplanSceneShootRequest _build() {
    final _$result = _$v ??
        _$ReplanSceneShootRequest._(
          plannedOrder: BuiltValueNullFieldError.checkNotNull(
              plannedOrder, r'ReplanSceneShootRequest', 'plannedOrder'),
          version: BuiltValueNullFieldError.checkNotNull(
              version, r'ReplanSceneShootRequest', 'version'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
