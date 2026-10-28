// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:breakdown_api/src/model/draft_outfit_origin_one_of_continued_from_scene.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'draft_outfit_origin_one_of.g.dart';

/// Pass 2 Option A: the character keeps wearing the look of an earlier scene. `source_draft_ref` is the preview row the look was read from, so the apply can bind this scene's beat to the SAME `Outfit` aggregate instead of creating a second look (design D3).
///
/// Properties:
/// * [continuedFromScene]
@BuiltValue()
abstract class DraftOutfitOriginOneOf
    implements Built<DraftOutfitOriginOneOf, DraftOutfitOriginOneOfBuilder> {
  @BuiltValueField(wireName: r'continued_from_scene')
  DraftOutfitOriginOneOfContinuedFromScene get continuedFromScene;

  DraftOutfitOriginOneOf._();

  factory DraftOutfitOriginOneOf(
          [void updates(DraftOutfitOriginOneOfBuilder b)]) =
      _$DraftOutfitOriginOneOf;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(DraftOutfitOriginOneOfBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<DraftOutfitOriginOneOf> get serializer =>
      _$DraftOutfitOriginOneOfSerializer();
}

class _$DraftOutfitOriginOneOfSerializer
    implements PrimitiveSerializer<DraftOutfitOriginOneOf> {
  @override
  final Iterable<Type> types = const [
    DraftOutfitOriginOneOf,
    _$DraftOutfitOriginOneOf
  ];

  @override
  final String wireName = r'DraftOutfitOriginOneOf';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    DraftOutfitOriginOneOf object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'continued_from_scene';
    yield serializers.serialize(
      object.continuedFromScene,
      specifiedType: const FullType(DraftOutfitOriginOneOfContinuedFromScene),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    DraftOutfitOriginOneOf object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object,
            specifiedType: specifiedType)
        .toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required DraftOutfitOriginOneOfBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'continued_from_scene':
          final valueDes = serializers.deserialize(
            value,
            specifiedType:
                const FullType(DraftOutfitOriginOneOfContinuedFromScene),
          ) as DraftOutfitOriginOneOfContinuedFromScene;
          result.continuedFromScene.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  DraftOutfitOriginOneOf deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = DraftOutfitOriginOneOfBuilder();
    final serializedList = (serialized as Iterable<Object?>).toList();
    final unhandled = <Object?>[];
    _deserializeProperties(
      serializers,
      serialized,
      specifiedType: specifiedType,
      serializedList: serializedList,
      unhandled: unhandled,
      result: result,
    );
    return result.build();
  }
}
