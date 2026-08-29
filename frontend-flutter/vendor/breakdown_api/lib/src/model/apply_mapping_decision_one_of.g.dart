// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'apply_mapping_decision_one_of.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ApplyMappingDecisionOneOf extends ApplyMappingDecisionOneOf {
  @override
  final ApplyMappingDecisionOneOfUpdate decisionUpdate;

  factory _$ApplyMappingDecisionOneOf(
          [void Function(ApplyMappingDecisionOneOfBuilder)? updates]) =>
      (ApplyMappingDecisionOneOfBuilder()..update(updates))._build();

  _$ApplyMappingDecisionOneOf._({required this.decisionUpdate}) : super._();
  @override
  ApplyMappingDecisionOneOf rebuild(
          void Function(ApplyMappingDecisionOneOfBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ApplyMappingDecisionOneOfBuilder toBuilder() =>
      ApplyMappingDecisionOneOfBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ApplyMappingDecisionOneOf &&
        decisionUpdate == other.decisionUpdate;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, decisionUpdate.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'ApplyMappingDecisionOneOf')
          ..add('decisionUpdate', decisionUpdate))
        .toString();
  }
}

class ApplyMappingDecisionOneOfBuilder
    implements
        Builder<ApplyMappingDecisionOneOf, ApplyMappingDecisionOneOfBuilder> {
  _$ApplyMappingDecisionOneOf? _$v;

  ApplyMappingDecisionOneOfUpdateBuilder? _decisionUpdate;
  ApplyMappingDecisionOneOfUpdateBuilder get decisionUpdate =>
      _$this._decisionUpdate ??= ApplyMappingDecisionOneOfUpdateBuilder();
  set decisionUpdate(ApplyMappingDecisionOneOfUpdateBuilder? decisionUpdate) =>
      _$this._decisionUpdate = decisionUpdate;

  ApplyMappingDecisionOneOfBuilder() {
    ApplyMappingDecisionOneOf._defaults(this);
  }

  ApplyMappingDecisionOneOfBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _decisionUpdate = $v.decisionUpdate.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ApplyMappingDecisionOneOf other) {
    _$v = other as _$ApplyMappingDecisionOneOf;
  }

  @override
  void update(void Function(ApplyMappingDecisionOneOfBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ApplyMappingDecisionOneOf build() => _build();

  _$ApplyMappingDecisionOneOf _build() {
    _$ApplyMappingDecisionOneOf _$result;
    try {
      _$result = _$v ??
          _$ApplyMappingDecisionOneOf._(
            decisionUpdate: decisionUpdate.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'decisionUpdate';
        decisionUpdate.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'ApplyMappingDecisionOneOf', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
