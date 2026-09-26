// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:breakdown_api/src/model/scene_source_one_of_ai_extracted.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'scene_source_one_of.g.dart';

/// SceneSourceOneOf
///
/// Properties:
/// * [aiExtracted]
@BuiltValue()
abstract class SceneSourceOneOf
    implements Built<SceneSourceOneOf, SceneSourceOneOfBuilder> {
  @BuiltValueField(wireName: r'AiExtracted')
  SceneSourceOneOfAiExtracted get aiExtracted;

  SceneSourceOneOf._();

  factory SceneSourceOneOf([void updates(SceneSourceOneOfBuilder b)]) =
      _$SceneSourceOneOf;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(SceneSourceOneOfBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<SceneSourceOneOf> get serializer =>
      _$SceneSourceOneOfSerializer();
}

class _$SceneSourceOneOfSerializer
    implements PrimitiveSerializer<SceneSourceOneOf> {
  @override
  final Iterable<Type> types = const [SceneSourceOneOf, _$SceneSourceOneOf];

  @override
  final String wireName = r'SceneSourceOneOf';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    SceneSourceOneOf object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'AiExtracted';
    yield serializers.serialize(
      object.aiExtracted,
      specifiedType: const FullType(SceneSourceOneOfAiExtracted),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    SceneSourceOneOf object, {
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
    required SceneSourceOneOfBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'AiExtracted':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(SceneSourceOneOfAiExtracted),
          ) as SceneSourceOneOfAiExtracted;
          result.aiExtracted.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  SceneSourceOneOf deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = SceneSourceOneOfBuilder();
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
