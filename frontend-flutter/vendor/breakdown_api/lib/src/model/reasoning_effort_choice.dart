// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'reasoning_effort_choice.g.dart';

/// What a configuration stores: an explicit level, or \"let the system decide\".  Deliberately a VALUE rather than `Option<ReasoningEffort>` (2026-11-20 investigation). The generated Dart client omits `null` fields, so a nullable field can be set but never cleared from the app — the level would be a one-way door. `Auto` travels as the string `\"auto\"` and therefore says \"no explicit level\" unambiguously in both directions.  `Auto` means: the curated profile for this `(provider, model)` if one applies, otherwise the provider's own default. It is spelled \"Auto\" rather than \"provider default\" for exactly that reason.
class ReasoningEffortChoice extends EnumClass {
  @BuiltValueEnumConst(wireName: r'auto')
  static const ReasoningEffortChoice auto = _$auto;
  @BuiltValueEnumConst(wireName: r'minimal')
  static const ReasoningEffortChoice minimal = _$minimal;
  @BuiltValueEnumConst(wireName: r'low')
  static const ReasoningEffortChoice low = _$low;
  @BuiltValueEnumConst(wireName: r'medium')
  static const ReasoningEffortChoice medium = _$medium;
  @BuiltValueEnumConst(wireName: r'high')
  static const ReasoningEffortChoice high = _$high;

  static Serializer<ReasoningEffortChoice> get serializer =>
      _$reasoningEffortChoiceSerializer;

  const ReasoningEffortChoice._(String name) : super(name);

  static BuiltSet<ReasoningEffortChoice> get values => _$values;
  static ReasoningEffortChoice valueOf(String name) => _$valueOf(name);
}

/// Optionally, enum_class can generate a mixin to go with your enum for use
/// with Angular. It exposes your enum constants as getters. So, if you mix it
/// in to your Dart component class, the values become available to the
/// corresponding Angular template.
///
/// Trigger mixin generation by writing a line like this one next to your enum.
abstract class ReasoningEffortChoiceMixin = Object
    with _$ReasoningEffortChoiceMixin;
