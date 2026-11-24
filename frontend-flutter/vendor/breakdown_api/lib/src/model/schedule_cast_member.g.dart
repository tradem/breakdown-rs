// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'schedule_cast_member.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ScheduleCastMember extends ScheduleCastMember {
  @override
  final String characterName;
  @override
  final String code;
  @override
  final ScheduleRoleModifier? modifier;

  factory _$ScheduleCastMember(
          [void Function(ScheduleCastMemberBuilder)? updates]) =>
      (ScheduleCastMemberBuilder()..update(updates))._build();

  _$ScheduleCastMember._(
      {required this.characterName, required this.code, this.modifier})
      : super._();
  @override
  ScheduleCastMember rebuild(
          void Function(ScheduleCastMemberBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ScheduleCastMemberBuilder toBuilder() =>
      ScheduleCastMemberBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ScheduleCastMember &&
        characterName == other.characterName &&
        code == other.code &&
        modifier == other.modifier;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, characterName.hashCode);
    _$hash = $jc(_$hash, code.hashCode);
    _$hash = $jc(_$hash, modifier.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'ScheduleCastMember')
          ..add('characterName', characterName)
          ..add('code', code)
          ..add('modifier', modifier))
        .toString();
  }
}

class ScheduleCastMemberBuilder
    implements Builder<ScheduleCastMember, ScheduleCastMemberBuilder> {
  _$ScheduleCastMember? _$v;

  String? _characterName;
  String? get characterName => _$this._characterName;
  set characterName(String? characterName) =>
      _$this._characterName = characterName;

  String? _code;
  String? get code => _$this._code;
  set code(String? code) => _$this._code = code;

  ScheduleRoleModifier? _modifier;
  ScheduleRoleModifier? get modifier => _$this._modifier;
  set modifier(ScheduleRoleModifier? modifier) => _$this._modifier = modifier;

  ScheduleCastMemberBuilder() {
    ScheduleCastMember._defaults(this);
  }

  ScheduleCastMemberBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _characterName = $v.characterName;
      _code = $v.code;
      _modifier = $v.modifier;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ScheduleCastMember other) {
    _$v = other as _$ScheduleCastMember;
  }

  @override
  void update(void Function(ScheduleCastMemberBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ScheduleCastMember build() => _build();

  _$ScheduleCastMember _build() {
    final _$result = _$v ??
        _$ScheduleCastMember._(
          characterName: BuiltValueNullFieldError.checkNotNull(
              characterName, r'ScheduleCastMember', 'characterName'),
          code: BuiltValueNullFieldError.checkNotNull(
              code, r'ScheduleCastMember', 'code'),
          modifier: modifier,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
