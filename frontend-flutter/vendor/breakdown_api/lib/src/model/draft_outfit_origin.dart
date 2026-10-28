// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:breakdown_api/src/model/draft_outfit_origin_one_of_continued_from_scene.dart';
import 'package:breakdown_api/src/model/draft_outfit_origin_one_of1_inferred_from_context.dart';
import 'package:breakdown_api/src/model/draft_outfit_origin_one_of1.dart';
import 'package:breakdown_api/src/model/draft_outfit_origin_one_of.dart';
import 'dart:core';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';
import 'package:one_of/one_of.dart';

part 'draft_outfit_origin.g.dart';

/// How a [`DraftOutfit`] came into existence.  The distinction is what the grounding check turns on: an explicitly quoted outfit is verified verbatim against the chunk, a derived one is a look the model composed from a shorthand the block named. Both are grounded at the outfit level; neither carries a per-piece quote.  Pass 2 (OpenSpec change `ai-import-decision-outfit-continuity`) adds the two cross-scene origins. The quote deliberately stays on [`DraftOutfit::source_quote`]: a quote-carrying `ExplicitQuote` variant would duplicate it, and a preview stored with the former unit form (`\"explicit_quote\"`) could never deserialize into a struct variant. The origin classifies WHERE the look came from, the quote carries WHAT it was read out of.
///
/// Properties:
/// * [continuedFromScene]
/// * [inferredFromContext]
@BuiltValue()
abstract class DraftOutfitOrigin
    implements Built<DraftOutfitOrigin, DraftOutfitOriginBuilder> {
  /// One Of [DraftOutfitOriginOneOf], [DraftOutfitOriginOneOf1], [String]
  OneOf get oneOf;

  DraftOutfitOrigin._();

  factory DraftOutfitOrigin([void updates(DraftOutfitOriginBuilder b)]) =
      _$DraftOutfitOrigin;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(DraftOutfitOriginBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<DraftOutfitOrigin> get serializer =>
      _$DraftOutfitOriginSerializer();
}

class _$DraftOutfitOriginSerializer
    implements PrimitiveSerializer<DraftOutfitOrigin> {
  @override
  final Iterable<Type> types = const [DraftOutfitOrigin, _$DraftOutfitOrigin];

  @override
  final String wireName = r'DraftOutfitOrigin';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    DraftOutfitOrigin object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {}

  @override
  Object serialize(
    Serializers serializers,
    DraftOutfitOrigin object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final oneOf = object.oneOf;
    return serializers.serialize(oneOf.value,
        specifiedType: FullType(oneOf.valueType))!;
  }

  @override
  DraftOutfitOrigin deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = DraftOutfitOriginBuilder();
    Object? oneOfDataSrc;
    final targetType = const FullType(OneOf, [
      FullType(String),
      FullType(String),
      FullType(DraftOutfitOriginOneOf),
      FullType(DraftOutfitOriginOneOf1),
    ]);
    oneOfDataSrc = serialized;
    result.oneOf = serializers.deserialize(oneOfDataSrc,
        specifiedType: targetType) as OneOf;
    return result.build();
  }
}
