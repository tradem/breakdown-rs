// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'apply_mapping_decision.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ApplyMappingDecision extends ApplyMappingDecision {
  @override
  final OneOf oneOf;

  factory _$ApplyMappingDecision(
          [void Function(ApplyMappingDecisionBuilder)? updates]) =>
      (ApplyMappingDecisionBuilder()..update(updates))._build();

  _$ApplyMappingDecision._({required this.oneOf}) : super._();
  @override
  ApplyMappingDecision rebuild(
          void Function(ApplyMappingDecisionBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ApplyMappingDecisionBuilder toBuilder() =>
      ApplyMappingDecisionBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ApplyMappingDecision && oneOf == other.oneOf;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, oneOf.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'ApplyMappingDecision')
          ..add('oneOf', oneOf))
        .toString();
  }
}

class ApplyMappingDecisionBuilder
    implements Builder<ApplyMappingDecision, ApplyMappingDecisionBuilder> {
  _$ApplyMappingDecision? _$v;

  OneOf? _oneOf;
  OneOf? get oneOf => _$this._oneOf;
  set oneOf(OneOf? oneOf) => _$this._oneOf = oneOf;

  ApplyMappingDecisionBuilder() {
    ApplyMappingDecision._defaults(this);
  }

  ApplyMappingDecisionBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _oneOf = $v.oneOf;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ApplyMappingDecision other) {
    _$v = other as _$ApplyMappingDecision;
  }

  @override
  void update(void Function(ApplyMappingDecisionBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ApplyMappingDecision build() => _build();

  _$ApplyMappingDecision _build() {
    final _$result = _$v ??
        _$ApplyMappingDecision._(
          oneOf: BuiltValueNullFieldError.checkNotNull(
              oneOf, r'ApplyMappingDecision', 'oneOf'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
