// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:breakdown_api/src/model/scene_details.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'update_scene_details_request.g.dart';

/// UpdateSceneDetailsRequest
///
/// Properties:
/// * [details]
/// * [version] - Aggregate version for optimistic locking.  The canonical version contract is **1-based**: `AggregateVersion::INITIAL = 1`, and every mutation increments the version by one.  The SierraDB stream version (0-based) is an infrastructure-internal detail. The translation rule is: `domain_version = stream_version + 1` (and inversely `stream_version = domain_version - 1`) which is performed exclusively inside `crates::infra` at the `*Commands` adapter boundary. `core` does not reference `stream_version`, `ExpectedVersion`, or `CurrentVersion`.
@BuiltValue()
abstract class UpdateSceneDetailsRequest
    implements
        Built<UpdateSceneDetailsRequest, UpdateSceneDetailsRequestBuilder> {
  @BuiltValueField(wireName: r'details')
  SceneDetails get details;

  /// Aggregate version for optimistic locking.  The canonical version contract is **1-based**: `AggregateVersion::INITIAL = 1`, and every mutation increments the version by one.  The SierraDB stream version (0-based) is an infrastructure-internal detail. The translation rule is: `domain_version = stream_version + 1` (and inversely `stream_version = domain_version - 1`) which is performed exclusively inside `crates::infra` at the `*Commands` adapter boundary. `core` does not reference `stream_version`, `ExpectedVersion`, or `CurrentVersion`.
  @BuiltValueField(wireName: r'version')
  int get version;

  UpdateSceneDetailsRequest._();

  factory UpdateSceneDetailsRequest(
          [void updates(UpdateSceneDetailsRequestBuilder b)]) =
      _$UpdateSceneDetailsRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(UpdateSceneDetailsRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<UpdateSceneDetailsRequest> get serializer =>
      _$UpdateSceneDetailsRequestSerializer();
}

class _$UpdateSceneDetailsRequestSerializer
    implements PrimitiveSerializer<UpdateSceneDetailsRequest> {
  @override
  final Iterable<Type> types = const [
    UpdateSceneDetailsRequest,
    _$UpdateSceneDetailsRequest
  ];

  @override
  final String wireName = r'UpdateSceneDetailsRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    UpdateSceneDetailsRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'details';
    yield serializers.serialize(
      object.details,
      specifiedType: const FullType(SceneDetails),
    );
    yield r'version';
    yield serializers.serialize(
      object.version,
      specifiedType: const FullType(int),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    UpdateSceneDetailsRequest object, {
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
    required UpdateSceneDetailsRequestBuilder result,
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
        case r'version':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.version = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  UpdateSceneDetailsRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = UpdateSceneDetailsRequestBuilder();
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
