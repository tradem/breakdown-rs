// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:breakdown_api/src/model/scene_details.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'create_scene_request.g.dart';

/// CreateSceneRequest
///
/// Properties:
/// * [details]
/// * [episodeId] - Opaque identifier for an `Episode` aggregate.
@BuiltValue()
abstract class CreateSceneRequest
    implements Built<CreateSceneRequest, CreateSceneRequestBuilder> {
  @BuiltValueField(wireName: r'details')
  SceneDetails get details;

  /// Opaque identifier for an `Episode` aggregate.
  @BuiltValueField(wireName: r'episode_id')
  String get episodeId;

  CreateSceneRequest._();

  factory CreateSceneRequest([void updates(CreateSceneRequestBuilder b)]) =
      _$CreateSceneRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(CreateSceneRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<CreateSceneRequest> get serializer =>
      _$CreateSceneRequestSerializer();
}

class _$CreateSceneRequestSerializer
    implements PrimitiveSerializer<CreateSceneRequest> {
  @override
  final Iterable<Type> types = const [CreateSceneRequest, _$CreateSceneRequest];

  @override
  final String wireName = r'CreateSceneRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    CreateSceneRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'details';
    yield serializers.serialize(
      object.details,
      specifiedType: const FullType(SceneDetails),
    );
    yield r'episode_id';
    yield serializers.serialize(
      object.episodeId,
      specifiedType: const FullType(String),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    CreateSceneRequest object, {
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
    required CreateSceneRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'details':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(SceneDetails),
          ) as SceneDetails;
          result.details.replace(valueDes);
          break;
        case r'episode_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.episodeId = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  CreateSceneRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = CreateSceneRequestBuilder();
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
