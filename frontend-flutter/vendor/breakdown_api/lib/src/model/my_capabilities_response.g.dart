// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'my_capabilities_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$MyCapabilitiesResponse extends MyCapabilitiesResponse {
  @override
  final bool hasActiveCredentialRole;
  @override
  final bool hasActiveOpsRole;

  factory _$MyCapabilitiesResponse(
          [void Function(MyCapabilitiesResponseBuilder)? updates]) =>
      (MyCapabilitiesResponseBuilder()..update(updates))._build();

  _$MyCapabilitiesResponse._(
      {required this.hasActiveCredentialRole, required this.hasActiveOpsRole})
      : super._();
  @override
  MyCapabilitiesResponse rebuild(
          void Function(MyCapabilitiesResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  MyCapabilitiesResponseBuilder toBuilder() =>
      MyCapabilitiesResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is MyCapabilitiesResponse &&
        hasActiveCredentialRole == other.hasActiveCredentialRole &&
        hasActiveOpsRole == other.hasActiveOpsRole;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, hasActiveCredentialRole.hashCode);
    _$hash = $jc(_$hash, hasActiveOpsRole.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'MyCapabilitiesResponse')
          ..add('hasActiveCredentialRole', hasActiveCredentialRole)
          ..add('hasActiveOpsRole', hasActiveOpsRole))
        .toString();
  }
}

class MyCapabilitiesResponseBuilder
    implements Builder<MyCapabilitiesResponse, MyCapabilitiesResponseBuilder> {
  _$MyCapabilitiesResponse? _$v;

  bool? _hasActiveCredentialRole;
  bool? get hasActiveCredentialRole => _$this._hasActiveCredentialRole;
  set hasActiveCredentialRole(bool? hasActiveCredentialRole) =>
      _$this._hasActiveCredentialRole = hasActiveCredentialRole;

  bool? _hasActiveOpsRole;
  bool? get hasActiveOpsRole => _$this._hasActiveOpsRole;
  set hasActiveOpsRole(bool? hasActiveOpsRole) =>
      _$this._hasActiveOpsRole = hasActiveOpsRole;

  MyCapabilitiesResponseBuilder() {
    MyCapabilitiesResponse._defaults(this);
  }

  MyCapabilitiesResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _hasActiveCredentialRole = $v.hasActiveCredentialRole;
      _hasActiveOpsRole = $v.hasActiveOpsRole;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(MyCapabilitiesResponse other) {
    _$v = other as _$MyCapabilitiesResponse;
  }

  @override
  void update(void Function(MyCapabilitiesResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  MyCapabilitiesResponse build() => _build();

  _$MyCapabilitiesResponse _build() {
    final _$result = _$v ??
        _$MyCapabilitiesResponse._(
          hasActiveCredentialRole: BuiltValueNullFieldError.checkNotNull(
              hasActiveCredentialRole,
              r'MyCapabilitiesResponse',
              'hasActiveCredentialRole'),
          hasActiveOpsRole: BuiltValueNullFieldError.checkNotNull(
              hasActiveOpsRole, r'MyCapabilitiesResponse', 'hasActiveOpsRole'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
