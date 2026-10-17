// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'token_cost_breakdown.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$TokenCostBreakdown extends TokenCostBreakdown {
  @override
  final int? cachedInputRateNanoPerMillion;
  @override
  final int cachedTokensIn;
  @override
  final int inputRateNanoPerMillion;
  @override
  final int outputRateNanoPerMillion;
  @override
  final int tokensIn;
  @override
  final int tokensOut;
  @override
  final int totalNano;

  factory _$TokenCostBreakdown(
          [void Function(TokenCostBreakdownBuilder)? updates]) =>
      (TokenCostBreakdownBuilder()..update(updates))._build();

  _$TokenCostBreakdown._(
      {this.cachedInputRateNanoPerMillion,
      required this.cachedTokensIn,
      required this.inputRateNanoPerMillion,
      required this.outputRateNanoPerMillion,
      required this.tokensIn,
      required this.tokensOut,
      required this.totalNano})
      : super._();
  @override
  TokenCostBreakdown rebuild(
          void Function(TokenCostBreakdownBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  TokenCostBreakdownBuilder toBuilder() =>
      TokenCostBreakdownBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is TokenCostBreakdown &&
        cachedInputRateNanoPerMillion == other.cachedInputRateNanoPerMillion &&
        cachedTokensIn == other.cachedTokensIn &&
        inputRateNanoPerMillion == other.inputRateNanoPerMillion &&
        outputRateNanoPerMillion == other.outputRateNanoPerMillion &&
        tokensIn == other.tokensIn &&
        tokensOut == other.tokensOut &&
        totalNano == other.totalNano;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, cachedInputRateNanoPerMillion.hashCode);
    _$hash = $jc(_$hash, cachedTokensIn.hashCode);
    _$hash = $jc(_$hash, inputRateNanoPerMillion.hashCode);
    _$hash = $jc(_$hash, outputRateNanoPerMillion.hashCode);
    _$hash = $jc(_$hash, tokensIn.hashCode);
    _$hash = $jc(_$hash, tokensOut.hashCode);
    _$hash = $jc(_$hash, totalNano.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'TokenCostBreakdown')
          ..add('cachedInputRateNanoPerMillion', cachedInputRateNanoPerMillion)
          ..add('cachedTokensIn', cachedTokensIn)
          ..add('inputRateNanoPerMillion', inputRateNanoPerMillion)
          ..add('outputRateNanoPerMillion', outputRateNanoPerMillion)
          ..add('tokensIn', tokensIn)
          ..add('tokensOut', tokensOut)
          ..add('totalNano', totalNano))
        .toString();
  }
}

class TokenCostBreakdownBuilder
    implements Builder<TokenCostBreakdown, TokenCostBreakdownBuilder> {
  _$TokenCostBreakdown? _$v;

  int? _cachedInputRateNanoPerMillion;
  int? get cachedInputRateNanoPerMillion =>
      _$this._cachedInputRateNanoPerMillion;
  set cachedInputRateNanoPerMillion(int? cachedInputRateNanoPerMillion) =>
      _$this._cachedInputRateNanoPerMillion = cachedInputRateNanoPerMillion;

  int? _cachedTokensIn;
  int? get cachedTokensIn => _$this._cachedTokensIn;
  set cachedTokensIn(int? cachedTokensIn) =>
      _$this._cachedTokensIn = cachedTokensIn;

  int? _inputRateNanoPerMillion;
  int? get inputRateNanoPerMillion => _$this._inputRateNanoPerMillion;
  set inputRateNanoPerMillion(int? inputRateNanoPerMillion) =>
      _$this._inputRateNanoPerMillion = inputRateNanoPerMillion;

  int? _outputRateNanoPerMillion;
  int? get outputRateNanoPerMillion => _$this._outputRateNanoPerMillion;
  set outputRateNanoPerMillion(int? outputRateNanoPerMillion) =>
      _$this._outputRateNanoPerMillion = outputRateNanoPerMillion;

  int? _tokensIn;
  int? get tokensIn => _$this._tokensIn;
  set tokensIn(int? tokensIn) => _$this._tokensIn = tokensIn;

  int? _tokensOut;
  int? get tokensOut => _$this._tokensOut;
  set tokensOut(int? tokensOut) => _$this._tokensOut = tokensOut;

  int? _totalNano;
  int? get totalNano => _$this._totalNano;
  set totalNano(int? totalNano) => _$this._totalNano = totalNano;

  TokenCostBreakdownBuilder() {
    TokenCostBreakdown._defaults(this);
  }

  TokenCostBreakdownBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _cachedInputRateNanoPerMillion = $v.cachedInputRateNanoPerMillion;
      _cachedTokensIn = $v.cachedTokensIn;
      _inputRateNanoPerMillion = $v.inputRateNanoPerMillion;
      _outputRateNanoPerMillion = $v.outputRateNanoPerMillion;
      _tokensIn = $v.tokensIn;
      _tokensOut = $v.tokensOut;
      _totalNano = $v.totalNano;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(TokenCostBreakdown other) {
    _$v = other as _$TokenCostBreakdown;
  }

  @override
  void update(void Function(TokenCostBreakdownBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  TokenCostBreakdown build() => _build();

  _$TokenCostBreakdown _build() {
    final _$result = _$v ??
        _$TokenCostBreakdown._(
          cachedInputRateNanoPerMillion: cachedInputRateNanoPerMillion,
          cachedTokensIn: BuiltValueNullFieldError.checkNotNull(
              cachedTokensIn, r'TokenCostBreakdown', 'cachedTokensIn'),
          inputRateNanoPerMillion: BuiltValueNullFieldError.checkNotNull(
              inputRateNanoPerMillion,
              r'TokenCostBreakdown',
              'inputRateNanoPerMillion'),
          outputRateNanoPerMillion: BuiltValueNullFieldError.checkNotNull(
              outputRateNanoPerMillion,
              r'TokenCostBreakdown',
              'outputRateNanoPerMillion'),
          tokensIn: BuiltValueNullFieldError.checkNotNull(
              tokensIn, r'TokenCostBreakdown', 'tokensIn'),
          tokensOut: BuiltValueNullFieldError.checkNotNull(
              tokensOut, r'TokenCostBreakdown', 'tokensOut'),
          totalNano: BuiltValueNullFieldError.checkNotNull(
              totalNano, r'TokenCostBreakdown', 'totalNano'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
