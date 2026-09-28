// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'apply_mapping.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ApplyMapping extends ApplyMapping {
  @override
  final BuiltList<CostumeDecision>? costumeDecisions;
  @override
  final ApplyMappingDecision decision;
  @override
  final String draftRef;

  factory _$ApplyMapping([void Function(ApplyMappingBuilder)? updates]) =>
      (ApplyMappingBuilder()..update(updates))._build();

  _$ApplyMapping._(
      {this.costumeDecisions, required this.decision, required this.draftRef})
      : super._();
  @override
  ApplyMapping rebuild(void Function(ApplyMappingBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ApplyMappingBuilder toBuilder() => ApplyMappingBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ApplyMapping &&
        costumeDecisions == other.costumeDecisions &&
        decision == other.decision &&
        draftRef == other.draftRef;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, costumeDecisions.hashCode);
    _$hash = $jc(_$hash, decision.hashCode);
    _$hash = $jc(_$hash, draftRef.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'ApplyMapping')
          ..add('costumeDecisions', costumeDecisions)
          ..add('decision', decision)
          ..add('draftRef', draftRef))
        .toString();
  }
}

class ApplyMappingBuilder
    implements Builder<ApplyMapping, ApplyMappingBuilder> {
  _$ApplyMapping? _$v;

  ListBuilder<CostumeDecision>? _costumeDecisions;
  ListBuilder<CostumeDecision> get costumeDecisions =>
      _$this._costumeDecisions ??= ListBuilder<CostumeDecision>();
  set costumeDecisions(ListBuilder<CostumeDecision>? costumeDecisions) =>
      _$this._costumeDecisions = costumeDecisions;

  ApplyMappingDecisionBuilder? _decision;
  ApplyMappingDecisionBuilder get decision =>
      _$this._decision ??= ApplyMappingDecisionBuilder();
  set decision(ApplyMappingDecisionBuilder? decision) =>
      _$this._decision = decision;

  String? _draftRef;
  String? get draftRef => _$this._draftRef;
  set draftRef(String? draftRef) => _$this._draftRef = draftRef;

  ApplyMappingBuilder() {
    ApplyMapping._defaults(this);
  }

  ApplyMappingBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _costumeDecisions = $v.costumeDecisions?.toBuilder();
      _decision = $v.decision.toBuilder();
      _draftRef = $v.draftRef;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ApplyMapping other) {
    _$v = other as _$ApplyMapping;
  }

  @override
  void update(void Function(ApplyMappingBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ApplyMapping build() => _build();

  _$ApplyMapping _build() {
    _$ApplyMapping _$result;
    try {
      _$result = _$v ??
          _$ApplyMapping._(
            costumeDecisions: _costumeDecisions?.build(),
            decision: decision.build(),
            draftRef: BuiltValueNullFieldError.checkNotNull(
                draftRef, r'ApplyMapping', 'draftRef'),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'costumeDecisions';
        _costumeDecisions?.build();
        _$failedField = 'decision';
        decision.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'ApplyMapping', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
