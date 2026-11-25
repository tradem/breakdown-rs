// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'schedule_legend_entry.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ScheduleLegendEntry extends ScheduleLegendEntry {
  @override
  final String characterName;
  @override
  final String code;
  @override
  final ScheduleRoleModifier? modifier;

  factory _$ScheduleLegendEntry(
          [void Function(ScheduleLegendEntryBuilder)? updates]) =>
      (ScheduleLegendEntryBuilder()..update(updates))._build();

  _$ScheduleLegendEntry._(
      {required this.characterName, required this.code, this.modifier})
      : super._();
  @override
  ScheduleLegendEntry rebuild(
          void Function(ScheduleLegendEntryBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ScheduleLegendEntryBuilder toBuilder() =>
      ScheduleLegendEntryBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ScheduleLegendEntry &&
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
    return (newBuiltValueToStringHelper(r'ScheduleLegendEntry')
          ..add('characterName', characterName)
          ..add('code', code)
          ..add('modifier', modifier))
        .toString();
  }
}

class ScheduleLegendEntryBuilder
    implements Builder<ScheduleLegendEntry, ScheduleLegendEntryBuilder> {
  _$ScheduleLegendEntry? _$v;

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

  ScheduleLegendEntryBuilder() {
    ScheduleLegendEntry._defaults(this);
  }

  ScheduleLegendEntryBuilder get _$this {
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
  void replace(ScheduleLegendEntry other) {
    _$v = other as _$ScheduleLegendEntry;
  }

  @override
  void update(void Function(ScheduleLegendEntryBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ScheduleLegendEntry build() => _build();

  _$ScheduleLegendEntry _build() {
    final _$result = _$v ??
        _$ScheduleLegendEntry._(
          characterName: BuiltValueNullFieldError.checkNotNull(
              characterName, r'ScheduleLegendEntry', 'characterName'),
          code: BuiltValueNullFieldError.checkNotNull(
              code, r'ScheduleLegendEntry', 'code'),
          modifier: modifier,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
