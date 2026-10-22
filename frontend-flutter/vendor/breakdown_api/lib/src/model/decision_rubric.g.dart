// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'decision_rubric.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$DecisionRubric extends DecisionRubric {
  @override
  final String? decisionModel;
  @override
  final LlmProvider? decisionProvider;
  @override
  final double? groundingFactor;
  @override
  final bool? scoringFailed;
  @override
  final BuiltMap<String, double>? subScores;

  factory _$DecisionRubric([void Function(DecisionRubricBuilder)? updates]) =>
      (DecisionRubricBuilder()..update(updates))._build();

  _$DecisionRubric._(
      {this.decisionModel,
      this.decisionProvider,
      this.groundingFactor,
      this.scoringFailed,
      this.subScores})
      : super._();
  @override
  DecisionRubric rebuild(void Function(DecisionRubricBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  DecisionRubricBuilder toBuilder() => DecisionRubricBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is DecisionRubric &&
        decisionModel == other.decisionModel &&
        decisionProvider == other.decisionProvider &&
        groundingFactor == other.groundingFactor &&
        scoringFailed == other.scoringFailed &&
        subScores == other.subScores;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, decisionModel.hashCode);
    _$hash = $jc(_$hash, decisionProvider.hashCode);
    _$hash = $jc(_$hash, groundingFactor.hashCode);
    _$hash = $jc(_$hash, scoringFailed.hashCode);
    _$hash = $jc(_$hash, subScores.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'DecisionRubric')
          ..add('decisionModel', decisionModel)
          ..add('decisionProvider', decisionProvider)
          ..add('groundingFactor', groundingFactor)
          ..add('scoringFailed', scoringFailed)
          ..add('subScores', subScores))
        .toString();
  }
}

class DecisionRubricBuilder
    implements Builder<DecisionRubric, DecisionRubricBuilder> {
  _$DecisionRubric? _$v;

  String? _decisionModel;
  String? get decisionModel => _$this._decisionModel;
  set decisionModel(String? decisionModel) =>
      _$this._decisionModel = decisionModel;

  LlmProvider? _decisionProvider;
  LlmProvider? get decisionProvider => _$this._decisionProvider;
  set decisionProvider(LlmProvider? decisionProvider) =>
      _$this._decisionProvider = decisionProvider;

  double? _groundingFactor;
  double? get groundingFactor => _$this._groundingFactor;
  set groundingFactor(double? groundingFactor) =>
      _$this._groundingFactor = groundingFactor;

  bool? _scoringFailed;
  bool? get scoringFailed => _$this._scoringFailed;
  set scoringFailed(bool? scoringFailed) =>
      _$this._scoringFailed = scoringFailed;

  MapBuilder<String, double>? _subScores;
  MapBuilder<String, double> get subScores =>
      _$this._subScores ??= MapBuilder<String, double>();
  set subScores(MapBuilder<String, double>? subScores) =>
      _$this._subScores = subScores;

  DecisionRubricBuilder() {
    DecisionRubric._defaults(this);
  }

  DecisionRubricBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _decisionModel = $v.decisionModel;
      _decisionProvider = $v.decisionProvider;
      _groundingFactor = $v.groundingFactor;
      _scoringFailed = $v.scoringFailed;
      _subScores = $v.subScores?.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(DecisionRubric other) {
    _$v = other as _$DecisionRubric;
  }

  @override
  void update(void Function(DecisionRubricBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  DecisionRubric build() => _build();

  _$DecisionRubric _build() {
    _$DecisionRubric _$result;
    try {
      _$result = _$v ??
          _$DecisionRubric._(
            decisionModel: decisionModel,
            decisionProvider: decisionProvider,
            groundingFactor: groundingFactor,
            scoringFailed: scoringFailed,
            subScores: _subScores?.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'subScores';
        _subScores?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'DecisionRubric', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
