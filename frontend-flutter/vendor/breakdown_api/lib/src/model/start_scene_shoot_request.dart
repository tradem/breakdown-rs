// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'start_scene_shoot_request.g.dart';

/// StartSceneShootRequest
///
/// Properties:
/// * [startDt]
/// * [version] - Aggregate version for optimistic locking.  The canonical version contract is **1-based**: `AggregateVersion::INITIAL = 1`, and every mutation increments the version by one.  The SierraDB stream version (0-based) is an infrastructure-internal detail. The translation rule is: `domain_version = stream_version + 1` (and inversely `stream_version = domain_version - 1`) which is performed exclusively inside `crates::infra` at the `*Commands` adapter boundary. `core` does not reference `stream_version`, `ExpectedVersion`, or `CurrentVersion`.
@BuiltValue()
abstract class StartSceneShootRequest
    implements Built<StartSceneShootRequest, StartSceneShootRequestBuilder> {
  @BuiltValueField(wireName: r'start_dt')
  DateTime? get startDt;

  /// Aggregate version for optimistic locking.  The canonical version contract is **1-based**: `AggregateVersion::INITIAL = 1`, and every mutation increments the version by one.  The SierraDB stream version (0-based) is an infrastructure-internal detail. The translation rule is: `domain_version = stream_version + 1` (and inversely `stream_version = domain_version - 1`) which is performed exclusively inside `crates::infra` at the `*Commands` adapter boundary. `core` does not reference `stream_version`, `ExpectedVersion`, or `CurrentVersion`.
  @BuiltValueField(wireName: r'version')
  int get version;

  StartSceneShootRequest._();

  factory StartSceneShootRequest(
          [void updates(StartSceneShootRequestBuilder b)]) =
      _$StartSceneShootRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(StartSceneShootRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<StartSceneShootRequest> get serializer =>
      _$StartSceneShootRequestSerializer();
}

class _$StartSceneShootRequestSerializer
    implements PrimitiveSerializer<StartSceneShootRequest> {
  @override
  final Iterable<Type> types = const [
    StartSceneShootRequest,
    _$StartSceneShootRequest
  ];

  @override
  final String wireName = r'StartSceneShootRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    StartSceneShootRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.startDt != null) {
      yield r'start_dt';
      yield serializers.serialize(
        object.startDt,
        specifiedType: const FullType.nullable(DateTime),
      );
    }
    yield r'version';
    yield serializers.serialize(
      object.version,
      specifiedType: const FullType(int),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    StartSceneShootRequest object, {
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
    required StartSceneShootRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'start_dt':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(DateTime),
          ) as DateTime?;
          if (valueDes == null) continue;
          result.startDt = valueDes;
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
  StartSceneShootRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = StartSceneShootRequestBuilder();
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
