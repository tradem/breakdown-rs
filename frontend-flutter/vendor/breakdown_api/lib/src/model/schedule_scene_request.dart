// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'schedule_scene_request.g.dart';

/// Request body for linking a `Scene` to a `ShootingDay`.
///
/// Properties:
/// * [shootingDayId] - Opaque identifier for a `ShootingDay` aggregate.  A `ShootingDay` is an Episode-scoped scheduling unit (a Drehtag). It is its own event-sourced aggregate, so it gets a dedicated UUIDv7 opaque id that is never decoded inside `core`.
/// * [version] - Aggregate version for optimistic locking.  The canonical version contract is **1-based**: `AggregateVersion::INITIAL = 1`, and every mutation increments the version by one.  The SierraDB stream version (0-based) is an infrastructure-internal detail. The translation rule is: `domain_version = stream_version + 1` (and inversely `stream_version = domain_version - 1`) which is performed exclusively inside `crates::infra` at the `*Commands` adapter boundary. `core` does not reference `stream_version`, `ExpectedVersion`, or `CurrentVersion`.
@BuiltValue()
abstract class ScheduleSceneRequest
    implements Built<ScheduleSceneRequest, ScheduleSceneRequestBuilder> {
  /// Opaque identifier for a `ShootingDay` aggregate.  A `ShootingDay` is an Episode-scoped scheduling unit (a Drehtag). It is its own event-sourced aggregate, so it gets a dedicated UUIDv7 opaque id that is never decoded inside `core`.
  @BuiltValueField(wireName: r'shooting_day_id')
  String get shootingDayId;

  /// Aggregate version for optimistic locking.  The canonical version contract is **1-based**: `AggregateVersion::INITIAL = 1`, and every mutation increments the version by one.  The SierraDB stream version (0-based) is an infrastructure-internal detail. The translation rule is: `domain_version = stream_version + 1` (and inversely `stream_version = domain_version - 1`) which is performed exclusively inside `crates::infra` at the `*Commands` adapter boundary. `core` does not reference `stream_version`, `ExpectedVersion`, or `CurrentVersion`.
  @BuiltValueField(wireName: r'version')
  int get version;

  ScheduleSceneRequest._();

  factory ScheduleSceneRequest([void updates(ScheduleSceneRequestBuilder b)]) =
      _$ScheduleSceneRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ScheduleSceneRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ScheduleSceneRequest> get serializer =>
      _$ScheduleSceneRequestSerializer();
}

class _$ScheduleSceneRequestSerializer
    implements PrimitiveSerializer<ScheduleSceneRequest> {
  @override
  final Iterable<Type> types = const [
    ScheduleSceneRequest,
    _$ScheduleSceneRequest
  ];

  @override
  final String wireName = r'ScheduleSceneRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ScheduleSceneRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'shooting_day_id';
    yield serializers.serialize(
      object.shootingDayId,
      specifiedType: const FullType(String),
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
    ScheduleSceneRequest object, {
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
    required ScheduleSceneRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'shooting_day_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.shootingDayId = valueDes;
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
  ScheduleSceneRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ScheduleSceneRequestBuilder();
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
