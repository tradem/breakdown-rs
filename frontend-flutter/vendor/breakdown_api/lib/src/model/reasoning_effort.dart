// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'reasoning_effort.g.dart';

/// Provider-side `reasoning_effort` a caller may request.  Deliberately a closed set with wire-stable names: a free-form string would let a typo reach a provider that answers `400` on every call of that configuration. The provider-specific extras (`max`, `xhigh`, `none`) are not modelled — every use case here is *reducing* effort, and the common denominator of the three catalogues is `low`/`medium`/`high`/`minimal`.
class ReasoningEffort extends EnumClass {
  @BuiltValueEnumConst(wireName: r'minimal')
  static const ReasoningEffort minimal = _$minimal;
  @BuiltValueEnumConst(wireName: r'low')
  static const ReasoningEffort low = _$low;
  @BuiltValueEnumConst(wireName: r'medium')
  static const ReasoningEffort medium = _$medium;
  @BuiltValueEnumConst(wireName: r'high')
  static const ReasoningEffort high = _$high;

  static Serializer<ReasoningEffort> get serializer =>
      _$reasoningEffortSerializer;

  const ReasoningEffort._(String name) : super(name);

  static BuiltSet<ReasoningEffort> get values => _$values;
  static ReasoningEffort valueOf(String name) => _$valueOf(name);
}

/// Optionally, enum_class can generate a mixin to go with your enum for use
/// with Angular. It exposes your enum constants as getters. So, if you mix it
/// in to your Dart component class, the values become available to the
/// corresponding Angular template.
///
/// Trigger mixin generation by writing a line like this one next to your enum.
abstract class ReasoningEffortMixin = Object with _$ReasoningEffortMixin;
