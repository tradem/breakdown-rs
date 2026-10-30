// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'decision_telemetry.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$DecisionTelemetry extends DecisionTelemetry {
  @override
  final int? failedRows;
  @override
  final String? model;
  @override
  final DecisionOutcome outcome;
  @override
  final LlmProvider? provider;

  factory _$DecisionTelemetry(
          [void Function(DecisionTelemetryBuilder)? updates]) =>
      (DecisionTelemetryBuilder()..update(updates))._build();

  _$DecisionTelemetry._(
      {this.failedRows, this.model, required this.outcome, this.provider})
      : super._();
  @override
  DecisionTelemetry rebuild(void Function(DecisionTelemetryBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  DecisionTelemetryBuilder toBuilder() =>
      DecisionTelemetryBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is DecisionTelemetry &&
        failedRows == other.failedRows &&
        model == other.model &&
        outcome == other.outcome &&
        provider == other.provider;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, failedRows.hashCode);
    _$hash = $jc(_$hash, model.hashCode);
    _$hash = $jc(_$hash, outcome.hashCode);
    _$hash = $jc(_$hash, provider.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'DecisionTelemetry')
          ..add('failedRows', failedRows)
          ..add('model', model)
          ..add('outcome', outcome)
          ..add('provider', provider))
        .toString();
  }
}

class DecisionTelemetryBuilder
    implements Builder<DecisionTelemetry, DecisionTelemetryBuilder> {
  _$DecisionTelemetry? _$v;

  int? _failedRows;
  int? get failedRows => _$this._failedRows;
  set failedRows(int? failedRows) => _$this._failedRows = failedRows;

  String? _model;
  String? get model => _$this._model;
  set model(String? model) => _$this._model = model;

  DecisionOutcome? _outcome;
  DecisionOutcome? get outcome => _$this._outcome;
  set outcome(DecisionOutcome? outcome) => _$this._outcome = outcome;

  LlmProvider? _provider;
  LlmProvider? get provider => _$this._provider;
  set provider(LlmProvider? provider) => _$this._provider = provider;

  DecisionTelemetryBuilder() {
    DecisionTelemetry._defaults(this);
  }

  DecisionTelemetryBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _failedRows = $v.failedRows;
      _model = $v.model;
      _outcome = $v.outcome;
      _provider = $v.provider;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(DecisionTelemetry other) {
    _$v = other as _$DecisionTelemetry;
  }

  @override
  void update(void Function(DecisionTelemetryBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  DecisionTelemetry build() => _build();

  _$DecisionTelemetry _build() {
    final _$result = _$v ??
        _$DecisionTelemetry._(
          failedRows: failedRows,
          model: model,
          outcome: BuiltValueNullFieldError.checkNotNull(
              outcome, r'DecisionTelemetry', 'outcome'),
          provider: provider,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
