// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'decision_outcome.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const DecisionOutcome _$ran = const DecisionOutcome._('ran');
const DecisionOutcome _$skippedNoConfig =
    const DecisionOutcome._('skippedNoConfig');
const DecisionOutcome _$clientUnavailable =
    const DecisionOutcome._('clientUnavailable');
const DecisionOutcome _$scoringFailed =
    const DecisionOutcome._('scoringFailed');
const DecisionOutcome _$skippedNotApplicable =
    const DecisionOutcome._('skippedNotApplicable');

DecisionOutcome _$valueOf(String name) {
  switch (name) {
    case 'ran':
      return _$ran;
    case 'skippedNoConfig':
      return _$skippedNoConfig;
    case 'clientUnavailable':
      return _$clientUnavailable;
    case 'scoringFailed':
      return _$scoringFailed;
    case 'skippedNotApplicable':
      return _$skippedNotApplicable;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<DecisionOutcome> _$values =
    BuiltSet<DecisionOutcome>(const <DecisionOutcome>[
  _$ran,
  _$skippedNoConfig,
  _$clientUnavailable,
  _$scoringFailed,
  _$skippedNotApplicable,
]);

class _$DecisionOutcomeMeta {
  const _$DecisionOutcomeMeta();
  DecisionOutcome get ran => _$ran;
  DecisionOutcome get skippedNoConfig => _$skippedNoConfig;
  DecisionOutcome get clientUnavailable => _$clientUnavailable;
  DecisionOutcome get scoringFailed => _$scoringFailed;
  DecisionOutcome get skippedNotApplicable => _$skippedNotApplicable;
  DecisionOutcome valueOf(String name) => _$valueOf(name);
  BuiltSet<DecisionOutcome> get values => _$values;
}

abstract class _$DecisionOutcomeMixin {
  // ignore: non_constant_identifier_names
  _$DecisionOutcomeMeta get DecisionOutcome => const _$DecisionOutcomeMeta();
}

Serializer<DecisionOutcome> _$decisionOutcomeSerializer =
    _$DecisionOutcomeSerializer();

class _$DecisionOutcomeSerializer
    implements PrimitiveSerializer<DecisionOutcome> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'ran': 'ran',
    'skippedNoConfig': 'skipped_no_config',
    'clientUnavailable': 'client_unavailable',
    'scoringFailed': 'scoring_failed',
    'skippedNotApplicable': 'skipped_not_applicable',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'ran': 'ran',
    'skipped_no_config': 'skippedNoConfig',
    'client_unavailable': 'clientUnavailable',
    'scoring_failed': 'scoringFailed',
    'skipped_not_applicable': 'skippedNotApplicable',
  };

  @override
  final Iterable<Type> types = const <Type>[DecisionOutcome];
  @override
  final String wireName = 'DecisionOutcome';

  @override
  Object serialize(Serializers serializers, DecisionOutcome object,
          {FullType specifiedType = FullType.unspecified}) =>
      _toWire[object.name] ?? object.name;

  @override
  DecisionOutcome deserialize(Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      DecisionOutcome.valueOf(
          _fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
