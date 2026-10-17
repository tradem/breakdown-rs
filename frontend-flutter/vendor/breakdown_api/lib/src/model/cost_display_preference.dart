// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'cost_display_preference.g.dart';

/// The user's preferred primary cost display metric (issue #675).  Both token and energy costs are always persisted on completed jobs, so switching the preference re-renders historical job costs without recalculation. `Token` is the default for every pre-existing `AiConfig` (replayed events and deserialized views without the field).
class CostDisplayPreference extends EnumClass {
  @BuiltValueEnumConst(wireName: r'token')
  static const CostDisplayPreference token = _$token;
  @BuiltValueEnumConst(wireName: r'energy')
  static const CostDisplayPreference energy = _$energy;

  static Serializer<CostDisplayPreference> get serializer =>
      _$costDisplayPreferenceSerializer;

  const CostDisplayPreference._(String name) : super(name);

  static BuiltSet<CostDisplayPreference> get values => _$values;
  static CostDisplayPreference valueOf(String name) => _$valueOf(name);
}

/// Optionally, enum_class can generate a mixin to go with your enum for use
/// with Angular. It exposes your enum constants as getters. So, if you mix it
/// in to your Dart component class, the values become available to the
/// corresponding Angular template.
///
/// Trigger mixin generation by writing a line like this one next to your enum.
abstract class CostDisplayPreferenceMixin = Object
    with _$CostDisplayPreferenceMixin;
