// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'apply_run_outcome_one_of1_failed.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ApplyRunOutcomeOneOf1Failed extends ApplyRunOutcomeOneOf1Failed {
  @override
  final String code;

  factory _$ApplyRunOutcomeOneOf1Failed(
          [void Function(ApplyRunOutcomeOneOf1FailedBuilder)? updates]) =>
      (ApplyRunOutcomeOneOf1FailedBuilder()..update(updates))._build();

  _$ApplyRunOutcomeOneOf1Failed._({required this.code}) : super._();
  @override
  ApplyRunOutcomeOneOf1Failed rebuild(
          void Function(ApplyRunOutcomeOneOf1FailedBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ApplyRunOutcomeOneOf1FailedBuilder toBuilder() =>
      ApplyRunOutcomeOneOf1FailedBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ApplyRunOutcomeOneOf1Failed && code == other.code;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, code.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'ApplyRunOutcomeOneOf1Failed')
          ..add('code', code))
        .toString();
  }
}

class ApplyRunOutcomeOneOf1FailedBuilder
    implements
        Builder<ApplyRunOutcomeOneOf1Failed,
            ApplyRunOutcomeOneOf1FailedBuilder> {
  _$ApplyRunOutcomeOneOf1Failed? _$v;

  String? _code;
  String? get code => _$this._code;
  set code(String? code) => _$this._code = code;

  ApplyRunOutcomeOneOf1FailedBuilder() {
    ApplyRunOutcomeOneOf1Failed._defaults(this);
  }

  ApplyRunOutcomeOneOf1FailedBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _code = $v.code;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ApplyRunOutcomeOneOf1Failed other) {
    _$v = other as _$ApplyRunOutcomeOneOf1Failed;
  }

  @override
  void update(void Function(ApplyRunOutcomeOneOf1FailedBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ApplyRunOutcomeOneOf1Failed build() => _build();

  _$ApplyRunOutcomeOneOf1Failed _build() {
    final _$result = _$v ??
        _$ApplyRunOutcomeOneOf1Failed._(
          code: BuiltValueNullFieldError.checkNotNull(
              code, r'ApplyRunOutcomeOneOf1Failed', 'code'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
