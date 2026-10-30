// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'cost_total.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$CostTotal extends CostTotal {
  @override
  final Currency? currency;
  @override
  final CostTotalStatus status;
  @override
  final int? totalNano;

  factory _$CostTotal([void Function(CostTotalBuilder)? updates]) =>
      (CostTotalBuilder()..update(updates))._build();

  _$CostTotal._({this.currency, required this.status, this.totalNano})
      : super._();
  @override
  CostTotal rebuild(void Function(CostTotalBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  CostTotalBuilder toBuilder() => CostTotalBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is CostTotal &&
        currency == other.currency &&
        status == other.status &&
        totalNano == other.totalNano;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, currency.hashCode);
    _$hash = $jc(_$hash, status.hashCode);
    _$hash = $jc(_$hash, totalNano.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'CostTotal')
          ..add('currency', currency)
          ..add('status', status)
          ..add('totalNano', totalNano))
        .toString();
  }
}

class CostTotalBuilder implements Builder<CostTotal, CostTotalBuilder> {
  _$CostTotal? _$v;

  Currency? _currency;
  Currency? get currency => _$this._currency;
  set currency(Currency? currency) => _$this._currency = currency;

  CostTotalStatus? _status;
  CostTotalStatus? get status => _$this._status;
  set status(CostTotalStatus? status) => _$this._status = status;

  int? _totalNano;
  int? get totalNano => _$this._totalNano;
  set totalNano(int? totalNano) => _$this._totalNano = totalNano;

  CostTotalBuilder() {
    CostTotal._defaults(this);
  }

  CostTotalBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _currency = $v.currency;
      _status = $v.status;
      _totalNano = $v.totalNano;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(CostTotal other) {
    _$v = other as _$CostTotal;
  }

  @override
  void update(void Function(CostTotalBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  CostTotal build() => _build();

  _$CostTotal _build() {
    final _$result = _$v ??
        _$CostTotal._(
          currency: currency,
          status: BuiltValueNullFieldError.checkNotNull(
              status, r'CostTotal', 'status'),
          totalNano: totalNano,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
