// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'model_pricing.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ModelPricing extends ModelPricing {
  @override
  final int? cachedInputNanoPerMillion;
  @override
  final Currency currency;
  @override
  final bool? energyCappedByToken;
  @override
  final int? energyNanoPerKwh;
  @override
  final int? imageNanoPerUnit;
  @override
  final int? imageOutputNanoPerMillion;
  @override
  final int inputNanoPerMillion;
  @override
  final int outputNanoPerMillion;
  @override
  final DateTime priceAsOf;
  @override
  final PricingSource pricingSource;

  factory _$ModelPricing([void Function(ModelPricingBuilder)? updates]) =>
      (ModelPricingBuilder()..update(updates))._build();

  _$ModelPricing._(
      {this.cachedInputNanoPerMillion,
      required this.currency,
      this.energyCappedByToken,
      this.energyNanoPerKwh,
      this.imageNanoPerUnit,
      this.imageOutputNanoPerMillion,
      required this.inputNanoPerMillion,
      required this.outputNanoPerMillion,
      required this.priceAsOf,
      required this.pricingSource})
      : super._();
  @override
  ModelPricing rebuild(void Function(ModelPricingBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ModelPricingBuilder toBuilder() => ModelPricingBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ModelPricing &&
        cachedInputNanoPerMillion == other.cachedInputNanoPerMillion &&
        currency == other.currency &&
        energyCappedByToken == other.energyCappedByToken &&
        energyNanoPerKwh == other.energyNanoPerKwh &&
        imageNanoPerUnit == other.imageNanoPerUnit &&
        imageOutputNanoPerMillion == other.imageOutputNanoPerMillion &&
        inputNanoPerMillion == other.inputNanoPerMillion &&
        outputNanoPerMillion == other.outputNanoPerMillion &&
        priceAsOf == other.priceAsOf &&
        pricingSource == other.pricingSource;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, cachedInputNanoPerMillion.hashCode);
    _$hash = $jc(_$hash, currency.hashCode);
    _$hash = $jc(_$hash, energyCappedByToken.hashCode);
    _$hash = $jc(_$hash, energyNanoPerKwh.hashCode);
    _$hash = $jc(_$hash, imageNanoPerUnit.hashCode);
    _$hash = $jc(_$hash, imageOutputNanoPerMillion.hashCode);
    _$hash = $jc(_$hash, inputNanoPerMillion.hashCode);
    _$hash = $jc(_$hash, outputNanoPerMillion.hashCode);
    _$hash = $jc(_$hash, priceAsOf.hashCode);
    _$hash = $jc(_$hash, pricingSource.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'ModelPricing')
          ..add('cachedInputNanoPerMillion', cachedInputNanoPerMillion)
          ..add('currency', currency)
          ..add('energyCappedByToken', energyCappedByToken)
          ..add('energyNanoPerKwh', energyNanoPerKwh)
          ..add('imageNanoPerUnit', imageNanoPerUnit)
          ..add('imageOutputNanoPerMillion', imageOutputNanoPerMillion)
          ..add('inputNanoPerMillion', inputNanoPerMillion)
          ..add('outputNanoPerMillion', outputNanoPerMillion)
          ..add('priceAsOf', priceAsOf)
          ..add('pricingSource', pricingSource))
        .toString();
  }
}

class ModelPricingBuilder
    implements Builder<ModelPricing, ModelPricingBuilder> {
  _$ModelPricing? _$v;

  int? _cachedInputNanoPerMillion;
  int? get cachedInputNanoPerMillion => _$this._cachedInputNanoPerMillion;
  set cachedInputNanoPerMillion(int? cachedInputNanoPerMillion) =>
      _$this._cachedInputNanoPerMillion = cachedInputNanoPerMillion;

  Currency? _currency;
  Currency? get currency => _$this._currency;
  set currency(Currency? currency) => _$this._currency = currency;

  bool? _energyCappedByToken;
  bool? get energyCappedByToken => _$this._energyCappedByToken;
  set energyCappedByToken(bool? energyCappedByToken) =>
      _$this._energyCappedByToken = energyCappedByToken;

  int? _energyNanoPerKwh;
  int? get energyNanoPerKwh => _$this._energyNanoPerKwh;
  set energyNanoPerKwh(int? energyNanoPerKwh) =>
      _$this._energyNanoPerKwh = energyNanoPerKwh;

  int? _imageNanoPerUnit;
  int? get imageNanoPerUnit => _$this._imageNanoPerUnit;
  set imageNanoPerUnit(int? imageNanoPerUnit) =>
      _$this._imageNanoPerUnit = imageNanoPerUnit;

  int? _imageOutputNanoPerMillion;
  int? get imageOutputNanoPerMillion => _$this._imageOutputNanoPerMillion;
  set imageOutputNanoPerMillion(int? imageOutputNanoPerMillion) =>
      _$this._imageOutputNanoPerMillion = imageOutputNanoPerMillion;

  int? _inputNanoPerMillion;
  int? get inputNanoPerMillion => _$this._inputNanoPerMillion;
  set inputNanoPerMillion(int? inputNanoPerMillion) =>
      _$this._inputNanoPerMillion = inputNanoPerMillion;

  int? _outputNanoPerMillion;
  int? get outputNanoPerMillion => _$this._outputNanoPerMillion;
  set outputNanoPerMillion(int? outputNanoPerMillion) =>
      _$this._outputNanoPerMillion = outputNanoPerMillion;

  DateTime? _priceAsOf;
  DateTime? get priceAsOf => _$this._priceAsOf;
  set priceAsOf(DateTime? priceAsOf) => _$this._priceAsOf = priceAsOf;

  PricingSource? _pricingSource;
  PricingSource? get pricingSource => _$this._pricingSource;
  set pricingSource(PricingSource? pricingSource) =>
      _$this._pricingSource = pricingSource;

  ModelPricingBuilder() {
    ModelPricing._defaults(this);
  }

  ModelPricingBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _cachedInputNanoPerMillion = $v.cachedInputNanoPerMillion;
      _currency = $v.currency;
      _energyCappedByToken = $v.energyCappedByToken;
      _energyNanoPerKwh = $v.energyNanoPerKwh;
      _imageNanoPerUnit = $v.imageNanoPerUnit;
      _imageOutputNanoPerMillion = $v.imageOutputNanoPerMillion;
      _inputNanoPerMillion = $v.inputNanoPerMillion;
      _outputNanoPerMillion = $v.outputNanoPerMillion;
      _priceAsOf = $v.priceAsOf;
      _pricingSource = $v.pricingSource;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ModelPricing other) {
    _$v = other as _$ModelPricing;
  }

  @override
  void update(void Function(ModelPricingBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ModelPricing build() => _build();

  _$ModelPricing _build() {
    final _$result = _$v ??
        _$ModelPricing._(
          cachedInputNanoPerMillion: cachedInputNanoPerMillion,
          currency: BuiltValueNullFieldError.checkNotNull(
              currency, r'ModelPricing', 'currency'),
          energyCappedByToken: energyCappedByToken,
          energyNanoPerKwh: energyNanoPerKwh,
          imageNanoPerUnit: imageNanoPerUnit,
          imageOutputNanoPerMillion: imageOutputNanoPerMillion,
          inputNanoPerMillion: BuiltValueNullFieldError.checkNotNull(
              inputNanoPerMillion, r'ModelPricing', 'inputNanoPerMillion'),
          outputNanoPerMillion: BuiltValueNullFieldError.checkNotNull(
              outputNanoPerMillion, r'ModelPricing', 'outputNanoPerMillion'),
          priceAsOf: BuiltValueNullFieldError.checkNotNull(
              priceAsOf, r'ModelPricing', 'priceAsOf'),
          pricingSource: BuiltValueNullFieldError.checkNotNull(
              pricingSource, r'ModelPricing', 'pricingSource'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
