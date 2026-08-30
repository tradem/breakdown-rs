// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'grant_role_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$GrantRoleRequest extends GrantRoleRequest {
  @override
  final Role role;

  factory _$GrantRoleRequest(
          [void Function(GrantRoleRequestBuilder)? updates]) =>
      (GrantRoleRequestBuilder()..update(updates))._build();

  _$GrantRoleRequest._({required this.role}) : super._();
  @override
  GrantRoleRequest rebuild(void Function(GrantRoleRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  GrantRoleRequestBuilder toBuilder() =>
      GrantRoleRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is GrantRoleRequest && role == other.role;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, role.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'GrantRoleRequest')..add('role', role))
        .toString();
  }
}

class GrantRoleRequestBuilder
    implements Builder<GrantRoleRequest, GrantRoleRequestBuilder> {
  _$GrantRoleRequest? _$v;

  Role? _role;
  Role? get role => _$this._role;
  set role(Role? role) => _$this._role = role;

  GrantRoleRequestBuilder() {
    GrantRoleRequest._defaults(this);
  }

  GrantRoleRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _role = $v.role;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(GrantRoleRequest other) {
    _$v = other as _$GrantRoleRequest;
  }

  @override
  void update(void Function(GrantRoleRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  GrantRoleRequest build() => _build();

  _$GrantRoleRequest _build() {
    final _$result = _$v ??
        _$GrantRoleRequest._(
          role: BuiltValueNullFieldError.checkNotNull(
              role, r'GrantRoleRequest', 'role'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
