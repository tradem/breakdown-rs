// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'wrap_shooting_day_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$WrapShootingDayRequest extends WrapShootingDayRequest {
  @override
  final int version;

  factory _$WrapShootingDayRequest(
          [void Function(WrapShootingDayRequestBuilder)? updates]) =>
      (WrapShootingDayRequestBuilder()..update(updates))._build();

  _$WrapShootingDayRequest._({required this.version}) : super._();
  @override
  WrapShootingDayRequest rebuild(
          void Function(WrapShootingDayRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  WrapShootingDayRequestBuilder toBuilder() =>
      WrapShootingDayRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is WrapShootingDayRequest && version == other.version;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, version.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'WrapShootingDayRequest')
          ..add('version', version))
        .toString();
  }
}

class WrapShootingDayRequestBuilder
    implements Builder<WrapShootingDayRequest, WrapShootingDayRequestBuilder> {
  _$WrapShootingDayRequest? _$v;

  int? _version;
  int? get version => _$this._version;
  set version(int? version) => _$this._version = version;

  WrapShootingDayRequestBuilder() {
    WrapShootingDayRequest._defaults(this);
  }

  WrapShootingDayRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _version = $v.version;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(WrapShootingDayRequest other) {
    _$v = other as _$WrapShootingDayRequest;
  }

  @override
  void update(void Function(WrapShootingDayRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  WrapShootingDayRequest build() => _build();

  _$WrapShootingDayRequest _build() {
    final _$result = _$v ??
        _$WrapShootingDayRequest._(
          version: BuiltValueNullFieldError.checkNotNull(
              version, r'WrapShootingDayRequest', 'version'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
