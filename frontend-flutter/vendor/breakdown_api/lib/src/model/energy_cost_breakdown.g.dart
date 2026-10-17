// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'energy_cost_breakdown.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$EnergyCostBreakdown extends EnergyCostBreakdown {
  @override
  final bool cappedByTokenCost;
  @override
  final int effectiveCappedNano;
  @override
  final int energyMillijoules;
  @override
  final int rateNanoPerKwh;
  @override
  final int rawEnergyNano;

  factory _$EnergyCostBreakdown(
          [void Function(EnergyCostBreakdownBuilder)? updates]) =>
      (EnergyCostBreakdownBuilder()..update(updates))._build();

  _$EnergyCostBreakdown._(
      {required this.cappedByTokenCost,
      required this.effectiveCappedNano,
      required this.energyMillijoules,
      required this.rateNanoPerKwh,
      required this.rawEnergyNano})
      : super._();
  @override
  EnergyCostBreakdown rebuild(
          void Function(EnergyCostBreakdownBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  EnergyCostBreakdownBuilder toBuilder() =>
      EnergyCostBreakdownBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is EnergyCostBreakdown &&
        cappedByTokenCost == other.cappedByTokenCost &&
        effectiveCappedNano == other.effectiveCappedNano &&
        energyMillijoules == other.energyMillijoules &&
        rateNanoPerKwh == other.rateNanoPerKwh &&
        rawEnergyNano == other.rawEnergyNano;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, cappedByTokenCost.hashCode);
    _$hash = $jc(_$hash, effectiveCappedNano.hashCode);
    _$hash = $jc(_$hash, energyMillijoules.hashCode);
    _$hash = $jc(_$hash, rateNanoPerKwh.hashCode);
    _$hash = $jc(_$hash, rawEnergyNano.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'EnergyCostBreakdown')
          ..add('cappedByTokenCost', cappedByTokenCost)
          ..add('effectiveCappedNano', effectiveCappedNano)
          ..add('energyMillijoules', energyMillijoules)
          ..add('rateNanoPerKwh', rateNanoPerKwh)
          ..add('rawEnergyNano', rawEnergyNano))
        .toString();
  }
}

class EnergyCostBreakdownBuilder
    implements Builder<EnergyCostBreakdown, EnergyCostBreakdownBuilder> {
  _$EnergyCostBreakdown? _$v;

  bool? _cappedByTokenCost;
  bool? get cappedByTokenCost => _$this._cappedByTokenCost;
  set cappedByTokenCost(bool? cappedByTokenCost) =>
      _$this._cappedByTokenCost = cappedByTokenCost;

  int? _effectiveCappedNano;
  int? get effectiveCappedNano => _$this._effectiveCappedNano;
  set effectiveCappedNano(int? effectiveCappedNano) =>
      _$this._effectiveCappedNano = effectiveCappedNano;

  int? _energyMillijoules;
  int? get energyMillijoules => _$this._energyMillijoules;
  set energyMillijoules(int? energyMillijoules) =>
      _$this._energyMillijoules = energyMillijoules;

  int? _rateNanoPerKwh;
  int? get rateNanoPerKwh => _$this._rateNanoPerKwh;
  set rateNanoPerKwh(int? rateNanoPerKwh) =>
      _$this._rateNanoPerKwh = rateNanoPerKwh;

  int? _rawEnergyNano;
  int? get rawEnergyNano => _$this._rawEnergyNano;
  set rawEnergyNano(int? rawEnergyNano) =>
      _$this._rawEnergyNano = rawEnergyNano;

  EnergyCostBreakdownBuilder() {
    EnergyCostBreakdown._defaults(this);
  }

  EnergyCostBreakdownBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _cappedByTokenCost = $v.cappedByTokenCost;
      _effectiveCappedNano = $v.effectiveCappedNano;
      _energyMillijoules = $v.energyMillijoules;
      _rateNanoPerKwh = $v.rateNanoPerKwh;
      _rawEnergyNano = $v.rawEnergyNano;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(EnergyCostBreakdown other) {
    _$v = other as _$EnergyCostBreakdown;
  }

  @override
  void update(void Function(EnergyCostBreakdownBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  EnergyCostBreakdown build() => _build();

  _$EnergyCostBreakdown _build() {
    final _$result = _$v ??
        _$EnergyCostBreakdown._(
          cappedByTokenCost: BuiltValueNullFieldError.checkNotNull(
              cappedByTokenCost, r'EnergyCostBreakdown', 'cappedByTokenCost'),
          effectiveCappedNano: BuiltValueNullFieldError.checkNotNull(
              effectiveCappedNano,
              r'EnergyCostBreakdown',
              'effectiveCappedNano'),
          energyMillijoules: BuiltValueNullFieldError.checkNotNull(
              energyMillijoules, r'EnergyCostBreakdown', 'energyMillijoules'),
          rateNanoPerKwh: BuiltValueNullFieldError.checkNotNull(
              rateNanoPerKwh, r'EnergyCostBreakdown', 'rateNanoPerKwh'),
          rawEnergyNano: BuiltValueNullFieldError.checkNotNull(
              rawEnergyNano, r'EnergyCostBreakdown', 'rawEnergyNano'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
