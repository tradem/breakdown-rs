// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'outfit_decision.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$OutfitDecision extends OutfitDecision {
  @override
  final bool accepted;
  @override
  final int ordinal;

  factory _$OutfitDecision([void Function(OutfitDecisionBuilder)? updates]) =>
      (OutfitDecisionBuilder()..update(updates))._build();

  _$OutfitDecision._({required this.accepted, required this.ordinal})
      : super._();
  @override
  OutfitDecision rebuild(void Function(OutfitDecisionBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  OutfitDecisionBuilder toBuilder() => OutfitDecisionBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is OutfitDecision &&
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
    return (newBuiltValueToStringHelper(r'OutfitDecision')
          ..add('accepted', accepted)
          ..add('ordinal', ordinal))
        .toString();
  }
}

class OutfitDecisionBuilder
    implements Builder<OutfitDecision, OutfitDecisionBuilder> {
  _$OutfitDecision? _$v;

  bool? _accepted;
  bool? get accepted => _$this._accepted;
  set accepted(bool? accepted) => _$this._accepted = accepted;

  int? _ordinal;
  int? get ordinal => _$this._ordinal;
  set ordinal(int? ordinal) => _$this._ordinal = ordinal;

  OutfitDecisionBuilder() {
    OutfitDecision._defaults(this);
  }

  OutfitDecisionBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _accepted = $v.accepted;
      _ordinal = $v.ordinal;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(OutfitDecision other) {
    _$v = other as _$OutfitDecision;
  }

  @override
  void update(void Function(OutfitDecisionBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  OutfitDecision build() => _build();

  _$OutfitDecision _build() {
    final _$result = _$v ??
        _$OutfitDecision._(
          accepted: BuiltValueNullFieldError.checkNotNull(
              accepted, r'OutfitDecision', 'accepted'),
          ordinal: BuiltValueNullFieldError.checkNotNull(
              ordinal, r'OutfitDecision', 'ordinal'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
