// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'draft_outfit_origin_one_of_continued_from_scene.g.dart';

/// Pass 2 Option A: the character keeps wearing the look of an earlier scene. `source_draft_ref` is the preview row the look was read from, so the apply can bind this scene's beat to the SAME `Outfit` aggregate instead of creating a second look (design D3).
///
/// Properties:
/// * [confidence] - The Decision Model's calibrated probability of the continuation.
/// * [sourceDraftRef] - `draft_ref` of the source preview row ([`DraftScene::draft_ref`]).
/// * [sourceSceneNumber] - The source row's document scene number, when it carries one.
@BuiltValue()
abstract class DraftOutfitOriginOneOfContinuedFromScene
    implements
        Built<DraftOutfitOriginOneOfContinuedFromScene,
            DraftOutfitOriginOneOfContinuedFromSceneBuilder> {
  /// The Decision Model's calibrated probability of the continuation.
  @BuiltValueField(wireName: r'confidence')
  double get confidence;

  /// `draft_ref` of the source preview row ([`DraftScene::draft_ref`]).
  @BuiltValueField(wireName: r'source_draft_ref')
  String get sourceDraftRef;

  /// The source row's document scene number, when it carries one.
  @BuiltValueField(wireName: r'source_scene_number')
  int? get sourceSceneNumber;

  DraftOutfitOriginOneOfContinuedFromScene._();

  factory DraftOutfitOriginOneOfContinuedFromScene(
          [void updates(DraftOutfitOriginOneOfContinuedFromSceneBuilder b)]) =
      _$DraftOutfitOriginOneOfContinuedFromScene;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(DraftOutfitOriginOneOfContinuedFromSceneBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<DraftOutfitOriginOneOfContinuedFromScene> get serializer =>
      _$DraftOutfitOriginOneOfContinuedFromSceneSerializer();
}

class _$DraftOutfitOriginOneOfContinuedFromSceneSerializer
    implements PrimitiveSerializer<DraftOutfitOriginOneOfContinuedFromScene> {
  @override
  final Iterable<Type> types = const [
    DraftOutfitOriginOneOfContinuedFromScene,
    _$DraftOutfitOriginOneOfContinuedFromScene
  ];

  @override
  final String wireName = r'DraftOutfitOriginOneOfContinuedFromScene';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    DraftOutfitOriginOneOfContinuedFromScene object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'confidence';
    yield serializers.serialize(
      object.confidence,
      specifiedType: const FullType(double),
    );
    yield r'source_draft_ref';
    yield serializers.serialize(
      object.sourceDraftRef,
      specifiedType: const FullType(String),
    );
    if (object.sourceSceneNumber != null) {
      yield r'source_scene_number';
      yield serializers.serialize(
        object.sourceSceneNumber,
        specifiedType: const FullType.nullable(int),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    DraftOutfitOriginOneOfContinuedFromScene object, {
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
    required DraftOutfitOriginOneOfContinuedFromSceneBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'confidence':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(double),
          ) as double;
          result.confidence = valueDes;
          break;
        case r'source_draft_ref':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.sourceDraftRef = valueDes;
          break;
        case r'source_scene_number':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(int),
          ) as int?;
          if (valueDes == null) continue;
          result.sourceSceneNumber = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  DraftOutfitOriginOneOfContinuedFromScene deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = DraftOutfitOriginOneOfContinuedFromSceneBuilder();
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
