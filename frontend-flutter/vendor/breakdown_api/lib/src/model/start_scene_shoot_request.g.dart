// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'start_scene_shoot_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$StartSceneShootRequest extends StartSceneShootRequest {
  @override
  final DateTime? startDt;
  @override
  final int version;

  factory _$StartSceneShootRequest(
          [void Function(StartSceneShootRequestBuilder)? updates]) =>
      (StartSceneShootRequestBuilder()..update(updates))._build();

  _$StartSceneShootRequest._({this.startDt, required this.version}) : super._();
  @override
  StartSceneShootRequest rebuild(
          void Function(StartSceneShootRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  StartSceneShootRequestBuilder toBuilder() =>
      StartSceneShootRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is StartSceneShootRequest &&
        startDt == other.startDt &&
        version == other.version;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, startDt.hashCode);
    _$hash = $jc(_$hash, version.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'StartSceneShootRequest')
          ..add('startDt', startDt)
          ..add('version', version))
        .toString();
  }
}

class StartSceneShootRequestBuilder
    implements Builder<StartSceneShootRequest, StartSceneShootRequestBuilder> {
  _$StartSceneShootRequest? _$v;

  DateTime? _startDt;
  DateTime? get startDt => _$this._startDt;
  set startDt(DateTime? startDt) => _$this._startDt = startDt;

  int? _version;
  int? get version => _$this._version;
  set version(int? version) => _$this._version = version;

  StartSceneShootRequestBuilder() {
    StartSceneShootRequest._defaults(this);
  }

  StartSceneShootRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _startDt = $v.startDt;
      _version = $v.version;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(StartSceneShootRequest other) {
    _$v = other as _$StartSceneShootRequest;
  }

  @override
  void update(void Function(StartSceneShootRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  StartSceneShootRequest build() => _build();

  _$StartSceneShootRequest _build() {
    final _$result = _$v ??
        _$StartSceneShootRequest._(
          startDt: startDt,
          version: BuiltValueNullFieldError.checkNotNull(
              version, r'StartSceneShootRequest', 'version'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
