// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'finish_scene_shoot_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$FinishSceneShootRequest extends FinishSceneShootRequest {
  @override
  final DateTime? endDt;
  @override
  final int version;

  factory _$FinishSceneShootRequest(
          [void Function(FinishSceneShootRequestBuilder)? updates]) =>
      (FinishSceneShootRequestBuilder()..update(updates))._build();

  _$FinishSceneShootRequest._({this.endDt, required this.version}) : super._();
  @override
  FinishSceneShootRequest rebuild(
          void Function(FinishSceneShootRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  FinishSceneShootRequestBuilder toBuilder() =>
      FinishSceneShootRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is FinishSceneShootRequest &&
        endDt == other.endDt &&
        version == other.version;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, endDt.hashCode);
    _$hash = $jc(_$hash, version.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'FinishSceneShootRequest')
          ..add('endDt', endDt)
          ..add('version', version))
        .toString();
  }
}

class FinishSceneShootRequestBuilder
    implements
        Builder<FinishSceneShootRequest, FinishSceneShootRequestBuilder> {
  _$FinishSceneShootRequest? _$v;

  DateTime? _endDt;
  DateTime? get endDt => _$this._endDt;
  set endDt(DateTime? endDt) => _$this._endDt = endDt;

  int? _version;
  int? get version => _$this._version;
  set version(int? version) => _$this._version = version;

  FinishSceneShootRequestBuilder() {
    FinishSceneShootRequest._defaults(this);
  }

  FinishSceneShootRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _endDt = $v.endDt;
      _version = $v.version;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(FinishSceneShootRequest other) {
    _$v = other as _$FinishSceneShootRequest;
  }

  @override
  void update(void Function(FinishSceneShootRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  FinishSceneShootRequest build() => _build();

  _$FinishSceneShootRequest _build() {
    final _$result = _$v ??
        _$FinishSceneShootRequest._(
          endDt: endDt,
          version: BuiltValueNullFieldError.checkNotNull(
              version, r'FinishSceneShootRequest', 'version'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
