// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'skip_scene_shoot_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$SkipSceneShootRequest extends SkipSceneShootRequest {
  @override
  final int version;

  factory _$SkipSceneShootRequest(
          [void Function(SkipSceneShootRequestBuilder)? updates]) =>
      (SkipSceneShootRequestBuilder()..update(updates))._build();

  _$SkipSceneShootRequest._({required this.version}) : super._();
  @override
  SkipSceneShootRequest rebuild(
          void Function(SkipSceneShootRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  SkipSceneShootRequestBuilder toBuilder() =>
      SkipSceneShootRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is SkipSceneShootRequest && version == other.version;
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
    return (newBuiltValueToStringHelper(r'SkipSceneShootRequest')
          ..add('version', version))
        .toString();
  }
}

class SkipSceneShootRequestBuilder
    implements Builder<SkipSceneShootRequest, SkipSceneShootRequestBuilder> {
  _$SkipSceneShootRequest? _$v;

  int? _version;
  int? get version => _$this._version;
  set version(int? version) => _$this._version = version;

  SkipSceneShootRequestBuilder() {
    SkipSceneShootRequest._defaults(this);
  }

  SkipSceneShootRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _version = $v.version;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(SkipSceneShootRequest other) {
    _$v = other as _$SkipSceneShootRequest;
  }

  @override
  void update(void Function(SkipSceneShootRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  SkipSceneShootRequest build() => _build();

  _$SkipSceneShootRequest _build() {
    final _$result = _$v ??
        _$SkipSceneShootRequest._(
          version: BuiltValueNullFieldError.checkNotNull(
              version, r'SkipSceneShootRequest', 'version'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
