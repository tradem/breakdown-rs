// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'decision_cost_breakdown.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$DecisionCostBreakdown extends DecisionCostBreakdown {
  @override
  final int? cachedInputRateNanoPerMillion;
  @override
  final int cachedTokensIn;
  @override
  final Currency? currency;
  @override
  final int? energyCostNano;
  @override
  final int energyMillijoules;
  @override
  final int? energyRateNanoPerKwh;
  @override
  final int? inputRateNanoPerMillion;
  @override
  final String model;
  @override
  final int? outputRateNanoPerMillion;
  @override
  final DateTime? priceAsOf;
  @override
  final PricingSource? pricingSource;
  @override
  final LlmProvider provider;
  @override
  final CostStatus status;
  @override
  final int? tokenCostNano;
  @override
  final int tokensIn;
  @override
  final int tokensOut;

  factory _$DecisionCostBreakdown(
          [void Function(DecisionCostBreakdownBuilder)? updates]) =>
      (DecisionCostBreakdownBuilder()..update(updates))._build();

  _$DecisionCostBreakdown._(
      {this.cachedInputRateNanoPerMillion,
      required this.cachedTokensIn,
      this.currency,
      this.energyCostNano,
      required this.energyMillijoules,
      this.energyRateNanoPerKwh,
      this.inputRateNanoPerMillion,
      required this.model,
      this.outputRateNanoPerMillion,
      this.priceAsOf,
      this.pricingSource,
      required this.provider,
      required this.status,
      this.tokenCostNano,
      required this.tokensIn,
      required this.tokensOut})
      : super._();
  @override
  DecisionCostBreakdown rebuild(
          void Function(DecisionCostBreakdownBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  DecisionCostBreakdownBuilder toBuilder() =>
      DecisionCostBreakdownBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is DecisionCostBreakdown &&
        cachedInputRateNanoPerMillion == other.cachedInputRateNanoPerMillion &&
        cachedTokensIn == other.cachedTokensIn &&
        currency == other.currency &&
        energyCostNano == other.energyCostNano &&
        energyMillijoules == other.energyMillijoules &&
        energyRateNanoPerKwh == other.energyRateNanoPerKwh &&
        inputRateNanoPerMillion == other.inputRateNanoPerMillion &&
        model == other.model &&
        outputRateNanoPerMillion == other.outputRateNanoPerMillion &&
        priceAsOf == other.priceAsOf &&
        pricingSource == other.pricingSource &&
        provider == other.provider &&
        status == other.status &&
        tokenCostNano == other.tokenCostNano &&
        tokensIn == other.tokensIn &&
        tokensOut == other.tokensOut;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, cachedInputRateNanoPerMillion.hashCode);
    _$hash = $jc(_$hash, cachedTokensIn.hashCode);
    _$hash = $jc(_$hash, currency.hashCode);
    _$hash = $jc(_$hash, energyCostNano.hashCode);
    _$hash = $jc(_$hash, energyMillijoules.hashCode);
    _$hash = $jc(_$hash, energyRateNanoPerKwh.hashCode);
    _$hash = $jc(_$hash, inputRateNanoPerMillion.hashCode);
    _$hash = $jc(_$hash, model.hashCode);
    _$hash = $jc(_$hash, outputRateNanoPerMillion.hashCode);
    _$hash = $jc(_$hash, priceAsOf.hashCode);
    _$hash = $jc(_$hash, pricingSource.hashCode);
    _$hash = $jc(_$hash, provider.hashCode);
    _$hash = $jc(_$hash, status.hashCode);
    _$hash = $jc(_$hash, tokenCostNano.hashCode);
    _$hash = $jc(_$hash, tokensIn.hashCode);
    _$hash = $jc(_$hash, tokensOut.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'DecisionCostBreakdown')
          ..add('cachedInputRateNanoPerMillion', cachedInputRateNanoPerMillion)
          ..add('cachedTokensIn', cachedTokensIn)
          ..add('currency', currency)
          ..add('energyCostNano', energyCostNano)
          ..add('energyMillijoules', energyMillijoules)
          ..add('energyRateNanoPerKwh', energyRateNanoPerKwh)
          ..add('inputRateNanoPerMillion', inputRateNanoPerMillion)
          ..add('model', model)
          ..add('outputRateNanoPerMillion', outputRateNanoPerMillion)
          ..add('priceAsOf', priceAsOf)
          ..add('pricingSource', pricingSource)
          ..add('provider', provider)
          ..add('status', status)
          ..add('tokenCostNano', tokenCostNano)
          ..add('tokensIn', tokensIn)
          ..add('tokensOut', tokensOut))
        .toString();
  }
}

class DecisionCostBreakdownBuilder
    implements Builder<DecisionCostBreakdown, DecisionCostBreakdownBuilder> {
  _$DecisionCostBreakdown? _$v;

  int? _cachedInputRateNanoPerMillion;
  int? get cachedInputRateNanoPerMillion =>
      _$this._cachedInputRateNanoPerMillion;
  set cachedInputRateNanoPerMillion(int? cachedInputRateNanoPerMillion) =>
      _$this._cachedInputRateNanoPerMillion = cachedInputRateNanoPerMillion;

  int? _cachedTokensIn;
  int? get cachedTokensIn => _$this._cachedTokensIn;
  set cachedTokensIn(int? cachedTokensIn) =>
      _$this._cachedTokensIn = cachedTokensIn;

  Currency? _currency;
  Currency? get currency => _$this._currency;
  set currency(Currency? currency) => _$this._currency = currency;

  int? _energyCostNano;
  int? get energyCostNano => _$this._energyCostNano;
  set energyCostNano(int? energyCostNano) =>
      _$this._energyCostNano = energyCostNano;

  int? _energyMillijoules;
  int? get energyMillijoules => _$this._energyMillijoules;
  set energyMillijoules(int? energyMillijoules) =>
      _$this._energyMillijoules = energyMillijoules;

  int? _energyRateNanoPerKwh;
  int? get energyRateNanoPerKwh => _$this._energyRateNanoPerKwh;
  set energyRateNanoPerKwh(int? energyRateNanoPerKwh) =>
      _$this._energyRateNanoPerKwh = energyRateNanoPerKwh;

  int? _inputRateNanoPerMillion;
  int? get inputRateNanoPerMillion => _$this._inputRateNanoPerMillion;
  set inputRateNanoPerMillion(int? inputRateNanoPerMillion) =>
      _$this._inputRateNanoPerMillion = inputRateNanoPerMillion;

  String? _model;
  String? get model => _$this._model;
  set model(String? model) => _$this._model = model;

  int? _outputRateNanoPerMillion;
  int? get outputRateNanoPerMillion => _$this._outputRateNanoPerMillion;
  set outputRateNanoPerMillion(int? outputRateNanoPerMillion) =>
      _$this._outputRateNanoPerMillion = outputRateNanoPerMillion;

  DateTime? _priceAsOf;
  DateTime? get priceAsOf => _$this._priceAsOf;
  set priceAsOf(DateTime? priceAsOf) => _$this._priceAsOf = priceAsOf;

  PricingSource? _pricingSource;
  PricingSource? get pricingSource => _$this._pricingSource;
  set pricingSource(PricingSource? pricingSource) =>
      _$this._pricingSource = pricingSource;

  LlmProvider? _provider;
  LlmProvider? get provider => _$this._provider;
  set provider(LlmProvider? provider) => _$this._provider = provider;

  CostStatus? _status;
  CostStatus? get status => _$this._status;
  set status(CostStatus? status) => _$this._status = status;

  int? _tokenCostNano;
  int? get tokenCostNano => _$this._tokenCostNano;
  set tokenCostNano(int? tokenCostNano) =>
      _$this._tokenCostNano = tokenCostNano;

  int? _tokensIn;
  int? get tokensIn => _$this._tokensIn;
  set tokensIn(int? tokensIn) => _$this._tokensIn = tokensIn;

  int? _tokensOut;
  int? get tokensOut => _$this._tokensOut;
  set tokensOut(int? tokensOut) => _$this._tokensOut = tokensOut;

  DecisionCostBreakdownBuilder() {
    DecisionCostBreakdown._defaults(this);
  }

  DecisionCostBreakdownBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _cachedInputRateNanoPerMillion = $v.cachedInputRateNanoPerMillion;
      _cachedTokensIn = $v.cachedTokensIn;
      _currency = $v.currency;
      _energyCostNano = $v.energyCostNano;
      _energyMillijoules = $v.energyMillijoules;
      _energyRateNanoPerKwh = $v.energyRateNanoPerKwh;
      _inputRateNanoPerMillion = $v.inputRateNanoPerMillion;
      _model = $v.model;
      _outputRateNanoPerMillion = $v.outputRateNanoPerMillion;
      _priceAsOf = $v.priceAsOf;
      _pricingSource = $v.pricingSource;
      _provider = $v.provider;
      _status = $v.status;
      _tokenCostNano = $v.tokenCostNano;
      _tokensIn = $v.tokensIn;
      _tokensOut = $v.tokensOut;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(DecisionCostBreakdown other) {
    _$v = other as _$DecisionCostBreakdown;
  }

  @override
  void update(void Function(DecisionCostBreakdownBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  DecisionCostBreakdown build() => _build();

  _$DecisionCostBreakdown _build() {
    final _$result = _$v ??
        _$DecisionCostBreakdown._(
          cachedInputRateNanoPerMillion: cachedInputRateNanoPerMillion,
          cachedTokensIn: BuiltValueNullFieldError.checkNotNull(
              cachedTokensIn, r'DecisionCostBreakdown', 'cachedTokensIn'),
          currency: currency,
          energyCostNano: energyCostNano,
          energyMillijoules: BuiltValueNullFieldError.checkNotNull(
              energyMillijoules, r'DecisionCostBreakdown', 'energyMillijoules'),
          energyRateNanoPerKwh: energyRateNanoPerKwh,
          inputRateNanoPerMillion: inputRateNanoPerMillion,
          model: BuiltValueNullFieldError.checkNotNull(
              model, r'DecisionCostBreakdown', 'model'),
          outputRateNanoPerMillion: outputRateNanoPerMillion,
          priceAsOf: priceAsOf,
          pricingSource: pricingSource,
          provider: BuiltValueNullFieldError.checkNotNull(
              provider, r'DecisionCostBreakdown', 'provider'),
          status: BuiltValueNullFieldError.checkNotNull(
              status, r'DecisionCostBreakdown', 'status'),
          tokenCostNano: tokenCostNano,
          tokensIn: BuiltValueNullFieldError.checkNotNull(
              tokensIn, r'DecisionCostBreakdown', 'tokensIn'),
          tokensOut: BuiltValueNullFieldError.checkNotNull(
              tokensOut, r'DecisionCostBreakdown', 'tokensOut'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
