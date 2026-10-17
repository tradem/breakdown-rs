// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'cost_breakdown.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$CostBreakdown extends CostBreakdown {
  @override
  final Currency? currency;
  @override
  final EnergyCostBreakdown? energyCost;
  @override
  final ImageCostBreakdown? imageCost;
  @override
  final DateTime? priceAsOf;
  @override
  final PricingSource? pricingSource;
  @override
  final CostStatus status;
  @override
  final TokenCostBreakdown? tokenCost;

  factory _$CostBreakdown([void Function(CostBreakdownBuilder)? updates]) =>
      (CostBreakdownBuilder()..update(updates))._build();

  _$CostBreakdown._(
      {this.currency,
      this.energyCost,
      this.imageCost,
      this.priceAsOf,
      this.pricingSource,
      required this.status,
      this.tokenCost})
      : super._();
  @override
  CostBreakdown rebuild(void Function(CostBreakdownBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  CostBreakdownBuilder toBuilder() => CostBreakdownBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is CostBreakdown &&
        currency == other.currency &&
        energyCost == other.energyCost &&
        imageCost == other.imageCost &&
        priceAsOf == other.priceAsOf &&
        pricingSource == other.pricingSource &&
        status == other.status &&
        tokenCost == other.tokenCost;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, currency.hashCode);
    _$hash = $jc(_$hash, energyCost.hashCode);
    _$hash = $jc(_$hash, imageCost.hashCode);
    _$hash = $jc(_$hash, priceAsOf.hashCode);
    _$hash = $jc(_$hash, pricingSource.hashCode);
    _$hash = $jc(_$hash, status.hashCode);
    _$hash = $jc(_$hash, tokenCost.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'CostBreakdown')
          ..add('currency', currency)
          ..add('energyCost', energyCost)
          ..add('imageCost', imageCost)
          ..add('priceAsOf', priceAsOf)
          ..add('pricingSource', pricingSource)
          ..add('status', status)
          ..add('tokenCost', tokenCost))
        .toString();
  }
}

class CostBreakdownBuilder
    implements Builder<CostBreakdown, CostBreakdownBuilder> {
  _$CostBreakdown? _$v;

  Currency? _currency;
  Currency? get currency => _$this._currency;
  set currency(Currency? currency) => _$this._currency = currency;

  EnergyCostBreakdownBuilder? _energyCost;
  EnergyCostBreakdownBuilder get energyCost =>
      _$this._energyCost ??= EnergyCostBreakdownBuilder();
  set energyCost(EnergyCostBreakdownBuilder? energyCost) =>
      _$this._energyCost = energyCost;

  ImageCostBreakdownBuilder? _imageCost;
  ImageCostBreakdownBuilder get imageCost =>
      _$this._imageCost ??= ImageCostBreakdownBuilder();
  set imageCost(ImageCostBreakdownBuilder? imageCost) =>
      _$this._imageCost = imageCost;

  DateTime? _priceAsOf;
  DateTime? get priceAsOf => _$this._priceAsOf;
  set priceAsOf(DateTime? priceAsOf) => _$this._priceAsOf = priceAsOf;

  PricingSource? _pricingSource;
  PricingSource? get pricingSource => _$this._pricingSource;
  set pricingSource(PricingSource? pricingSource) =>
      _$this._pricingSource = pricingSource;

  CostStatus? _status;
  CostStatus? get status => _$this._status;
  set status(CostStatus? status) => _$this._status = status;

  TokenCostBreakdownBuilder? _tokenCost;
  TokenCostBreakdownBuilder get tokenCost =>
      _$this._tokenCost ??= TokenCostBreakdownBuilder();
  set tokenCost(TokenCostBreakdownBuilder? tokenCost) =>
      _$this._tokenCost = tokenCost;

  CostBreakdownBuilder() {
    CostBreakdown._defaults(this);
  }

  CostBreakdownBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _currency = $v.currency;
      _energyCost = $v.energyCost?.toBuilder();
      _imageCost = $v.imageCost?.toBuilder();
      _priceAsOf = $v.priceAsOf;
      _pricingSource = $v.pricingSource;
      _status = $v.status;
      _tokenCost = $v.tokenCost?.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(CostBreakdown other) {
    _$v = other as _$CostBreakdown;
  }

  @override
  void update(void Function(CostBreakdownBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  CostBreakdown build() => _build();

  _$CostBreakdown _build() {
    _$CostBreakdown _$result;
    try {
      _$result = _$v ??
          _$CostBreakdown._(
            currency: currency,
            energyCost: _energyCost?.build(),
            imageCost: _imageCost?.build(),
            priceAsOf: priceAsOf,
            pricingSource: pricingSource,
            status: BuiltValueNullFieldError.checkNotNull(
                status, r'CostBreakdown', 'status'),
            tokenCost: _tokenCost?.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'energyCost';
        _energyCost?.build();
        _$failedField = 'imageCost';
        _imageCost?.build();

        _$failedField = 'tokenCost';
        _tokenCost?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'CostBreakdown', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
