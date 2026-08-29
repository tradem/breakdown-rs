// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'invite_member_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$InviteMemberRequest extends InviteMemberRequest {
  @override
  final Role role;
  @override
  final String userId;

  factory _$InviteMemberRequest(
          [void Function(InviteMemberRequestBuilder)? updates]) =>
      (InviteMemberRequestBuilder()..update(updates))._build();

  _$InviteMemberRequest._({required this.role, required this.userId})
      : super._();
  @override
  InviteMemberRequest rebuild(
          void Function(InviteMemberRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  InviteMemberRequestBuilder toBuilder() =>
      InviteMemberRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is InviteMemberRequest &&
        role == other.role &&
        userId == other.userId;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, role.hashCode);
    _$hash = $jc(_$hash, userId.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'InviteMemberRequest')
          ..add('role', role)
          ..add('userId', userId))
        .toString();
  }
}

class InviteMemberRequestBuilder
    implements Builder<InviteMemberRequest, InviteMemberRequestBuilder> {
  _$InviteMemberRequest? _$v;

  Role? _role;
  Role? get role => _$this._role;
  set role(Role? role) => _$this._role = role;

  String? _userId;
  String? get userId => _$this._userId;
  set userId(String? userId) => _$this._userId = userId;

  InviteMemberRequestBuilder() {
    InviteMemberRequest._defaults(this);
  }

  InviteMemberRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _role = $v.role;
      _userId = $v.userId;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(InviteMemberRequest other) {
    _$v = other as _$InviteMemberRequest;
  }

  @override
  void update(void Function(InviteMemberRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  InviteMemberRequest build() => _build();

  _$InviteMemberRequest _build() {
    final _$result = _$v ??
        _$InviteMemberRequest._(
          role: BuiltValueNullFieldError.checkNotNull(
              role, r'InviteMemberRequest', 'role'),
          userId: BuiltValueNullFieldError.checkNotNull(
              userId, r'InviteMemberRequest', 'userId'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
