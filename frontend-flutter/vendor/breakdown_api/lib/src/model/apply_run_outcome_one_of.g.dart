// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'apply_run_outcome_one_of.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ApplyRunOutcomeOneOf extends ApplyRunOutcomeOneOf {
  @override
  final ApplyImportSummary succeeded;

  factory _$ApplyRunOutcomeOneOf(
          [void Function(ApplyRunOutcomeOneOfBuilder)? updates]) =>
      (ApplyRunOutcomeOneOfBuilder()..update(updates))._build();

  _$ApplyRunOutcomeOneOf._({required this.succeeded}) : super._();
  @override
  ApplyRunOutcomeOneOf rebuild(
          void Function(ApplyRunOutcomeOneOfBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ApplyRunOutcomeOneOfBuilder toBuilder() =>
      ApplyRunOutcomeOneOfBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ApplyRunOutcomeOneOf && succeeded == other.succeeded;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, succeeded.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'ApplyRunOutcomeOneOf')
          ..add('succeeded', succeeded))
        .toString();
  }
}

class ApplyRunOutcomeOneOfBuilder
    implements Builder<ApplyRunOutcomeOneOf, ApplyRunOutcomeOneOfBuilder> {
  _$ApplyRunOutcomeOneOf? _$v;

  ApplyImportSummaryBuilder? _succeeded;
  ApplyImportSummaryBuilder get succeeded =>
      _$this._succeeded ??= ApplyImportSummaryBuilder();
  set succeeded(ApplyImportSummaryBuilder? succeeded) =>
      _$this._succeeded = succeeded;

  ApplyRunOutcomeOneOfBuilder() {
    ApplyRunOutcomeOneOf._defaults(this);
  }

  ApplyRunOutcomeOneOfBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _succeeded = $v.succeeded.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ApplyRunOutcomeOneOf other) {
    _$v = other as _$ApplyRunOutcomeOneOf;
  }

  @override
  void update(void Function(ApplyRunOutcomeOneOfBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ApplyRunOutcomeOneOf build() => _build();

  _$ApplyRunOutcomeOneOf _build() {
    _$ApplyRunOutcomeOneOf _$result;
    try {
      _$result = _$v ??
          _$ApplyRunOutcomeOneOf._(
            succeeded: succeeded.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'succeeded';
        succeeded.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'ApplyRunOutcomeOneOf', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
