// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'schedule_scene_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ScheduleSceneRequest extends ScheduleSceneRequest {
  @override
  final String shootingDayId;
  @override
  final int version;

  factory _$ScheduleSceneRequest(
          [void Function(ScheduleSceneRequestBuilder)? updates]) =>
      (ScheduleSceneRequestBuilder()..update(updates))._build();

  _$ScheduleSceneRequest._({required this.shootingDayId, required this.version})
      : super._();
  @override
  ScheduleSceneRequest rebuild(
          void Function(ScheduleSceneRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ScheduleSceneRequestBuilder toBuilder() =>
      ScheduleSceneRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ScheduleSceneRequest &&
        shootingDayId == other.shootingDayId &&
        version == other.version;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, shootingDayId.hashCode);
    _$hash = $jc(_$hash, version.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'ScheduleSceneRequest')
          ..add('shootingDayId', shootingDayId)
          ..add('version', version))
        .toString();
  }
}

class ScheduleSceneRequestBuilder
    implements Builder<ScheduleSceneRequest, ScheduleSceneRequestBuilder> {
  _$ScheduleSceneRequest? _$v;

  String? _shootingDayId;
  String? get shootingDayId => _$this._shootingDayId;
  set shootingDayId(String? shootingDayId) =>
      _$this._shootingDayId = shootingDayId;

  int? _version;
  int? get version => _$this._version;
  set version(int? version) => _$this._version = version;

  ScheduleSceneRequestBuilder() {
    ScheduleSceneRequest._defaults(this);
  }

  ScheduleSceneRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _shootingDayId = $v.shootingDayId;
      _version = $v.version;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ScheduleSceneRequest other) {
    _$v = other as _$ScheduleSceneRequest;
  }

  @override
  void update(void Function(ScheduleSceneRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ScheduleSceneRequest build() => _build();

  _$ScheduleSceneRequest _build() {
    final _$result = _$v ??
        _$ScheduleSceneRequest._(
          shootingDayId: BuiltValueNullFieldError.checkNotNull(
              shootingDayId, r'ScheduleSceneRequest', 'shootingDayId'),
          version: BuiltValueNullFieldError.checkNotNull(
              version, r'ScheduleSceneRequest', 'version'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
