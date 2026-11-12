// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'apply_run_outcome_one_of1.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ApplyRunOutcomeOneOf1 extends ApplyRunOutcomeOneOf1 {
  @override
  final ApplyRunOutcomeOneOf1Failed failed;

  factory _$ApplyRunOutcomeOneOf1(
          [void Function(ApplyRunOutcomeOneOf1Builder)? updates]) =>
      (ApplyRunOutcomeOneOf1Builder()..update(updates))._build();

  _$ApplyRunOutcomeOneOf1._({required this.failed}) : super._();
  @override
  ApplyRunOutcomeOneOf1 rebuild(
          void Function(ApplyRunOutcomeOneOf1Builder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ApplyRunOutcomeOneOf1Builder toBuilder() =>
      ApplyRunOutcomeOneOf1Builder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ApplyRunOutcomeOneOf1 && failed == other.failed;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, failed.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'ApplyRunOutcomeOneOf1')
          ..add('failed', failed))
        .toString();
  }
}

class ApplyRunOutcomeOneOf1Builder
    implements Builder<ApplyRunOutcomeOneOf1, ApplyRunOutcomeOneOf1Builder> {
  _$ApplyRunOutcomeOneOf1? _$v;

  ApplyRunOutcomeOneOf1FailedBuilder? _failed;
  ApplyRunOutcomeOneOf1FailedBuilder get failed =>
      _$this._failed ??= ApplyRunOutcomeOneOf1FailedBuilder();
  set failed(ApplyRunOutcomeOneOf1FailedBuilder? failed) =>
      _$this._failed = failed;

  ApplyRunOutcomeOneOf1Builder() {
    ApplyRunOutcomeOneOf1._defaults(this);
  }

  ApplyRunOutcomeOneOf1Builder get _$this {
    final $v = _$v;
    if ($v != null) {
      _failed = $v.failed.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ApplyRunOutcomeOneOf1 other) {
    _$v = other as _$ApplyRunOutcomeOneOf1;
  }

  @override
  void update(void Function(ApplyRunOutcomeOneOf1Builder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ApplyRunOutcomeOneOf1 build() => _build();

  _$ApplyRunOutcomeOneOf1 _build() {
    _$ApplyRunOutcomeOneOf1 _$result;
    try {
      _$result = _$v ??
          _$ApplyRunOutcomeOneOf1._(
            failed: failed.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'failed';
        failed.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'ApplyRunOutcomeOneOf1', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
