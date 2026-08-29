// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'revoke_ai_config_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$RevokeAiConfigRequest extends RevokeAiConfigRequest {
  @override
  final int version;

  factory _$RevokeAiConfigRequest(
          [void Function(RevokeAiConfigRequestBuilder)? updates]) =>
      (RevokeAiConfigRequestBuilder()..update(updates))._build();

  _$RevokeAiConfigRequest._({required this.version}) : super._();
  @override
  RevokeAiConfigRequest rebuild(
          void Function(RevokeAiConfigRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  RevokeAiConfigRequestBuilder toBuilder() =>
      RevokeAiConfigRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is RevokeAiConfigRequest && version == other.version;
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
    return (newBuiltValueToStringHelper(r'RevokeAiConfigRequest')
          ..add('version', version))
        .toString();
  }
}

class RevokeAiConfigRequestBuilder
    implements Builder<RevokeAiConfigRequest, RevokeAiConfigRequestBuilder> {
  _$RevokeAiConfigRequest? _$v;

  int? _version;
  int? get version => _$this._version;
  set version(int? version) => _$this._version = version;

  RevokeAiConfigRequestBuilder() {
    RevokeAiConfigRequest._defaults(this);
  }

  RevokeAiConfigRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _version = $v.version;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(RevokeAiConfigRequest other) {
    _$v = other as _$RevokeAiConfigRequest;
  }

  @override
  void update(void Function(RevokeAiConfigRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  RevokeAiConfigRequest build() => _build();

  _$RevokeAiConfigRequest _build() {
    final _$result = _$v ??
        _$RevokeAiConfigRequest._(
          version: BuiltValueNullFieldError.checkNotNull(
              version, r'RevokeAiConfigRequest', 'version'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
