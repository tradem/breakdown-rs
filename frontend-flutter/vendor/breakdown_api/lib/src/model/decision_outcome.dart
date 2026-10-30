// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'decision_outcome.g.dart';

/// The outcome class of one job's Decision Model scoring pass (issue #767). The wire values are stable and additive: a client localizes its own copy per variant and never parses a free-text reason.
class DecisionOutcome extends EnumClass {
  @BuiltValueEnumConst(wireName: r'ran')
  static const DecisionOutcome ran = _$ran;
  @BuiltValueEnumConst(wireName: r'skipped_no_config')
  static const DecisionOutcome skippedNoConfig = _$skippedNoConfig;
  @BuiltValueEnumConst(wireName: r'client_unavailable')
  static const DecisionOutcome clientUnavailable = _$clientUnavailable;
  @BuiltValueEnumConst(wireName: r'scoring_failed')
  static const DecisionOutcome scoringFailed = _$scoringFailed;
  @BuiltValueEnumConst(wireName: r'skipped_not_applicable')
  static const DecisionOutcome skippedNotApplicable = _$skippedNotApplicable;

  static Serializer<DecisionOutcome> get serializer =>
      _$decisionOutcomeSerializer;

  const DecisionOutcome._(String name) : super(name);

  static BuiltSet<DecisionOutcome> get values => _$values;
  static DecisionOutcome valueOf(String name) => _$valueOf(name);
}

/// Optionally, enum_class can generate a mixin to go with your enum for use
/// with Angular. It exposes your enum constants as getters. So, if you mix it
/// in to your Dart component class, the values become available to the
/// corresponding Angular template.
///
/// Trigger mixin generation by writing a line like this one next to your enum.
abstract class DecisionOutcomeMixin = Object with _$DecisionOutcomeMixin;
