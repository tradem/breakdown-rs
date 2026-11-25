// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'schedule_role_modifier.g.dart';

/// Role modifier declared on a shooting-schedule `\"ROLLEN\"` legend entry (ADR-041 `D5`/`D6`, issue #960).
class ScheduleRoleModifier extends EnumClass {
  @BuiltValueEnumConst(wireName: r'none')
  static const ScheduleRoleModifier none = _$none;
  @BuiltValueEnumConst(wireName: r'dummy')
  static const ScheduleRoleModifier dummy = _$dummy;
  @BuiltValueEnumConst(wireName: r'voice_only')
  static const ScheduleRoleModifier voiceOnly = _$voiceOnly;
  @BuiltValueEnumConst(wireName: r'extra_ot')
  static const ScheduleRoleModifier extraOt = _$extraOt;

  static Serializer<ScheduleRoleModifier> get serializer =>
      _$scheduleRoleModifierSerializer;

  const ScheduleRoleModifier._(String name) : super(name);

  static BuiltSet<ScheduleRoleModifier> get values => _$values;
  static ScheduleRoleModifier valueOf(String name) => _$valueOf(name);
}

/// Optionally, enum_class can generate a mixin to go with your enum for use
/// with Angular. It exposes your enum constants as getters. So, if you mix it
/// in to your Dart component class, the values become available to the
/// corresponding Angular template.
///
/// Trigger mixin generation by writing a line like this one next to your enum.
abstract class ScheduleRoleModifierMixin = Object
    with _$ScheduleRoleModifierMixin;
