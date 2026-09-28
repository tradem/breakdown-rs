// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'costume_decision.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$CostumeDecision extends CostumeDecision {
  @override
  final bool accepted;
  @override
  final int ordinal;

  factory _$CostumeDecision([void Function(CostumeDecisionBuilder)? updates]) =>
      (CostumeDecisionBuilder()..update(updates))._build();

  _$CostumeDecision._({required this.accepted, required this.ordinal})
      : super._();
  @override
  CostumeDecision rebuild(void Function(CostumeDecisionBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  CostumeDecisionBuilder toBuilder() => CostumeDecisionBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is CostumeDecision &&
        accepted == other.accepted &&
        ordinal == other.ordinal;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, accepted.hashCode);
    _$hash = $jc(_$hash, ordinal.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'CostumeDecision')
          ..add('accepted', accepted)
          ..add('ordinal', ordinal))
        .toString();
  }
}

class CostumeDecisionBuilder
    implements Builder<CostumeDecision, CostumeDecisionBuilder> {
  _$CostumeDecision? _$v;

  bool? _accepted;
  bool? get accepted => _$this._accepted;
  set accepted(bool? accepted) => _$this._accepted = accepted;

  int? _ordinal;
  int? get ordinal => _$this._ordinal;
  set ordinal(int? ordinal) => _$this._ordinal = ordinal;

  CostumeDecisionBuilder() {
    CostumeDecision._defaults(this);
  }

  CostumeDecisionBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _accepted = $v.accepted;
      _ordinal = $v.ordinal;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(CostumeDecision other) {
    _$v = other as _$CostumeDecision;
  }

  @override
  void update(void Function(CostumeDecisionBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  CostumeDecision build() => _build();

  _$CostumeDecision _build() {
    final _$result = _$v ??
        _$CostumeDecision._(
          accepted: BuiltValueNullFieldError.checkNotNull(
              accepted, r'CostumeDecision', 'accepted'),
          ordinal: BuiltValueNullFieldError.checkNotNull(
              ordinal, r'CostumeDecision', 'ordinal'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
