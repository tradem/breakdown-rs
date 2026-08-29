// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'character_category.g.dart';

/// Exhaustive category for a Character.  Designed for **purely additive extension**: a new variant can be appended later without breaking deserialization of already-persisted data (existing rows only ever contain the original variants). Removing or renaming a variant is a *breaking* change and requires a separate proposal.  The single enum makes illegal states unrepresentable — there is no `(is_main_character = true, is_extra = true)` combination.
class CharacterCategory extends EnumClass {
  @BuiltValueEnumConst(wireName: r'main_cast')
  static const CharacterCategory mainCast = _$mainCast;
  @BuiltValueEnumConst(wireName: r'guest')
  static const CharacterCategory guest = _$guest;
  @BuiltValueEnumConst(wireName: r'extra')
  static const CharacterCategory extra = _$extra;

  static Serializer<CharacterCategory> get serializer =>
      _$characterCategorySerializer;

  const CharacterCategory._(String name) : super(name);

  static BuiltSet<CharacterCategory> get values => _$values;
  static CharacterCategory valueOf(String name) => _$valueOf(name);
}

/// Optionally, enum_class can generate a mixin to go with your enum for use
/// with Angular. It exposes your enum constants as getters. So, if you mix it
/// in to your Dart component class, the values become available to the
/// corresponding Angular template.
///
/// Trigger mixin generation by writing a line like this one next to your enum.
abstract class CharacterCategoryMixin = Object with _$CharacterCategoryMixin;
