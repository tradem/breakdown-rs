// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'draft_outfit_origin.g.dart';

/// How a [`DraftOutfit`] came into existence.  The distinction is what the grounding check turns on: an explicitly quoted outfit is verified verbatim against the chunk, a derived one is a look the model composed from a shorthand the block named. Both are grounded at the outfit level; neither carries a per-piece quote.
class DraftOutfitOrigin extends EnumClass {
  @BuiltValueEnumConst(wireName: r'explicit_quote')
  static const DraftOutfitOrigin explicitQuote = _$explicitQuote;
  @BuiltValueEnumConst(wireName: r'derived')
  static const DraftOutfitOrigin derived = _$derived;

  static Serializer<DraftOutfitOrigin> get serializer =>
      _$draftOutfitOriginSerializer;

  const DraftOutfitOrigin._(String name) : super(name);

  static BuiltSet<DraftOutfitOrigin> get values => _$values;
  static DraftOutfitOrigin valueOf(String name) => _$valueOf(name);
}

/// Optionally, enum_class can generate a mixin to go with your enum for use
/// with Angular. It exposes your enum constants as getters. So, if you mix it
/// in to your Dart component class, the values become available to the
/// corresponding Angular template.
///
/// Trigger mixin generation by writing a line like this one next to your enum.
abstract class DraftOutfitOriginMixin = Object with _$DraftOutfitOriginMixin;
