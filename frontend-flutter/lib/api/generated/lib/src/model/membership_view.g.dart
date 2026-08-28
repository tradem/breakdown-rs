// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'membership_view.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$MembershipView extends MembershipView {
  @override
  final String blockId;
  @override
  final DateTime joinedAt;
  @override
  final Role role;
  @override
  final MembershipStateKind state;
  @override
  final String userId;

  factory _$MembershipView([void Function(MembershipViewBuilder)? updates]) =>
      (MembershipViewBuilder()..update(updates))._build();

  _$MembershipView._(
      {required this.blockId,
      required this.joinedAt,
      required this.role,
      required this.state,
      required this.userId})
      : super._();
  @override
  MembershipView rebuild(void Function(MembershipViewBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  MembershipViewBuilder toBuilder() => MembershipViewBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is MembershipView &&
        blockId == other.blockId &&
        joinedAt == other.joinedAt &&
        role == other.role &&
        state == other.state &&
        userId == other.userId;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, blockId.hashCode);
    _$hash = $jc(_$hash, joinedAt.hashCode);
    _$hash = $jc(_$hash, role.hashCode);
    _$hash = $jc(_$hash, state.hashCode);
    _$hash = $jc(_$hash, userId.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'MembershipView')
          ..add('blockId', blockId)
          ..add('joinedAt', joinedAt)
          ..add('role', role)
          ..add('state', state)
          ..add('userId', userId))
        .toString();
  }
}

class MembershipViewBuilder
    implements Builder<MembershipView, MembershipViewBuilder> {
  _$MembershipView? _$v;

  String? _blockId;
  String? get blockId => _$this._blockId;
  set blockId(String? blockId) => _$this._blockId = blockId;

  DateTime? _joinedAt;
  DateTime? get joinedAt => _$this._joinedAt;
  set joinedAt(DateTime? joinedAt) => _$this._joinedAt = joinedAt;

  Role? _role;
  Role? get role => _$this._role;
  set role(Role? role) => _$this._role = role;

  MembershipStateKind? _state;
  MembershipStateKind? get state => _$this._state;
  set state(MembershipStateKind? state) => _$this._state = state;

  String? _userId;
  String? get userId => _$this._userId;
  set userId(String? userId) => _$this._userId = userId;

  MembershipViewBuilder() {
    MembershipView._defaults(this);
  }

  MembershipViewBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _blockId = $v.blockId;
      _joinedAt = $v.joinedAt;
      _role = $v.role;
      _state = $v.state;
      _userId = $v.userId;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(MembershipView other) {
    _$v = other as _$MembershipView;
  }

  @override
  void update(void Function(MembershipViewBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  MembershipView build() => _build();

  _$MembershipView _build() {
    final _$result = _$v ??
        _$MembershipView._(
          blockId: BuiltValueNullFieldError.checkNotNull(
              blockId, r'MembershipView', 'blockId'),
          joinedAt: BuiltValueNullFieldError.checkNotNull(
              joinedAt, r'MembershipView', 'joinedAt'),
          role: BuiltValueNullFieldError.checkNotNull(
              role, r'MembershipView', 'role'),
          state: BuiltValueNullFieldError.checkNotNull(
              state, r'MembershipView', 'state'),
          userId: BuiltValueNullFieldError.checkNotNull(
              userId, r'MembershipView', 'userId'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
