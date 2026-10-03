// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'unapplied_costume_reason.g.dart';

class UnappliedCostumeReason extends EnumClass {
  @BuiltValueEnumConst(wireName: r'character_not_planned')
  static const UnappliedCostumeReason characterNotPlanned =
      _$characterNotPlanned;
  @BuiltValueEnumConst(wireName: r'character_unavailable')
  static const UnappliedCostumeReason characterUnavailable =
      _$characterUnavailable;
  @BuiltValueEnumConst(wireName: r'create_rejected')
  static const UnappliedCostumeReason createRejected = _$createRejected;
  @BuiltValueEnumConst(wireName: r'notes_rejected')
  static const UnappliedCostumeReason notesRejected = _$notesRejected;
  @BuiltValueEnumConst(wireName: r'binding_rejected')
  static const UnappliedCostumeReason bindingRejected = _$bindingRejected;
  @BuiltValueEnumConst(wireName: r'beat_rejected')
  static const UnappliedCostumeReason beatRejected = _$beatRejected;

  static Serializer<UnappliedCostumeReason> get serializer =>
      _$unappliedCostumeReasonSerializer;

  const UnappliedCostumeReason._(String name) : super(name);

  static BuiltSet<UnappliedCostumeReason> get values => _$values;
  static UnappliedCostumeReason valueOf(String name) => _$valueOf(name);
}

/// Optionally, enum_class can generate a mixin to go with your enum for use
/// with Angular. It exposes your enum constants as getters. So, if you mix it
/// in to your Dart component class, the values become available to the
/// corresponding Angular template.
///
/// Trigger mixin generation by writing a line like this one next to your enum.
abstract class UnappliedCostumeReasonMixin = Object
    with _$UnappliedCostumeReasonMixin;
