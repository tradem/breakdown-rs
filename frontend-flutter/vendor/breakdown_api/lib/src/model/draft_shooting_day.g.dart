// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'draft_shooting_day.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$DraftShootingDay extends DraftShootingDay {
  @override
  final String? label;
  @override
  final int? number;
  @override
  final double? score;

  factory _$DraftShootingDay(
          [void Function(DraftShootingDayBuilder)? updates]) =>
      (DraftShootingDayBuilder()..update(updates))._build();

  _$DraftShootingDay._({this.label, this.number, this.score}) : super._();
  @override
  DraftShootingDay rebuild(void Function(DraftShootingDayBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  DraftShootingDayBuilder toBuilder() =>
      DraftShootingDayBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is DraftShootingDay &&
        label == other.label &&
        number == other.number &&
        score == other.score;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, label.hashCode);
    _$hash = $jc(_$hash, number.hashCode);
    _$hash = $jc(_$hash, score.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'DraftShootingDay')
          ..add('label', label)
          ..add('number', number)
          ..add('score', score))
        .toString();
  }
}

class DraftShootingDayBuilder
    implements Builder<DraftShootingDay, DraftShootingDayBuilder> {
  _$DraftShootingDay? _$v;

  String? _label;
  String? get label => _$this._label;
  set label(String? label) => _$this._label = label;

  int? _number;
  int? get number => _$this._number;
  set number(int? number) => _$this._number = number;

  double? _score;
  double? get score => _$this._score;
  set score(double? score) => _$this._score = score;

  DraftShootingDayBuilder() {
    DraftShootingDay._defaults(this);
  }

  DraftShootingDayBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _label = $v.label;
      _number = $v.number;
      _score = $v.score;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(DraftShootingDay other) {
    _$v = other as _$DraftShootingDay;
  }

  @override
  void update(void Function(DraftShootingDayBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  DraftShootingDay build() => _build();

  _$DraftShootingDay _build() {
    final _$result = _$v ??
        _$DraftShootingDay._(
          label: label,
          number: number,
          score: score,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
