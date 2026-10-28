// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'draft_outfit_origin.g.dart';

/// How a [`DraftOutfit`] came into existence.  The distinction is what the grounding check turns on: an explicitly quoted outfit is verified verbatim against the chunk, a derived one is a look the model composed from a shorthand the block named. Both are grounded at the outfit level; neither carries a per-piece quote.  Pass 2 (OpenSpec change `ai-import-decision-outfit-continuity`) adds the two cross-scene origins. Two deliberate properties:  - The quote stays on [`DraftOutfit::source_quote`]; a quote-carrying variant   would duplicate it and could drift from the fragment the grounding check   verified. - The enum stays **fieldless**, so the wire value is always a plain string. A   mixed enum (unit variants plus struct variants) lowers to a `oneOf` whose   two single-value string branches become two identical `string` alternatives   in the generated client, which then cannot decode `\"explicit_quote\"` at all   (`more than one match found`). The provenance payload therefore travels in   the separate [`DraftOutfit::provenance`] field.
class DraftOutfitOrigin extends EnumClass {
  @BuiltValueEnumConst(wireName: r'explicit_quote')
  static const DraftOutfitOrigin explicitQuote = _$explicitQuote;
  @BuiltValueEnumConst(wireName: r'derived')
  static const DraftOutfitOrigin derived = _$derived;
  @BuiltValueEnumConst(wireName: r'continued_from_scene')
  static const DraftOutfitOrigin continuedFromScene = _$continuedFromScene;
  @BuiltValueEnumConst(wireName: r'inferred_from_context')
  static const DraftOutfitOrigin inferredFromContext = _$inferredFromContext;

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
