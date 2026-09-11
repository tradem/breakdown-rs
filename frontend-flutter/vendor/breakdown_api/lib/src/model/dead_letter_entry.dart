// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'dead_letter_entry.g.dart';

/// One durably recorded poison event (row of `projection_dead_letter`).  Wire shape of `GET /v1/ops/projector-health` → `dead_letters`.
///
/// Properties:
/// * [attempts] - How often the event was dead-lettered (replays bump, never duplicate).
/// * [constraintName] - Violated constraint name, if the failure carried one.
/// * [errorMessage] - Rendered error message (`Debug` of the processor error).
/// * [eventName] - Recorded event type name (e.g. `CostumeAssigned`).
/// * [firstSeenAt]
/// * [lastSeenAt]
/// * [partitionId] - SierraDB partition the event stream hashed into.
/// * [projectionId] - Checkpoint projection id (the aggregate category, e.g. `costume`).
/// * [sequence] - Partition sequence of the poison event.
/// * [sqlstate] - Postgres SQLSTATE classifying the failure, if it carried one.
/// * [streamId] - SierraDB stream id the event belongs to.
@BuiltValue()
abstract class DeadLetterEntry
    implements Built<DeadLetterEntry, DeadLetterEntryBuilder> {
  /// How often the event was dead-lettered (replays bump, never duplicate).
  @BuiltValueField(wireName: r'attempts')
  int get attempts;

  /// Violated constraint name, if the failure carried one.
  @BuiltValueField(wireName: r'constraint_name')
  String? get constraintName;

  /// Rendered error message (`Debug` of the processor error).
  @BuiltValueField(wireName: r'error_message')
  String get errorMessage;

  /// Recorded event type name (e.g. `CostumeAssigned`).
  @BuiltValueField(wireName: r'event_name')
  String get eventName;

  @BuiltValueField(wireName: r'first_seen_at')
  DateTime get firstSeenAt;

  @BuiltValueField(wireName: r'last_seen_at')
  DateTime get lastSeenAt;

  /// SierraDB partition the event stream hashed into.
  @BuiltValueField(wireName: r'partition_id')
  int get partitionId;

  /// Checkpoint projection id (the aggregate category, e.g. `costume`).
  @BuiltValueField(wireName: r'projection_id')
  String get projectionId;

  /// Partition sequence of the poison event.
  @BuiltValueField(wireName: r'sequence')
  int get sequence;

  /// Postgres SQLSTATE classifying the failure, if it carried one.
  @BuiltValueField(wireName: r'sqlstate')
  String? get sqlstate;

  /// SierraDB stream id the event belongs to.
  @BuiltValueField(wireName: r'stream_id')
  String get streamId;

  DeadLetterEntry._();

  factory DeadLetterEntry([void updates(DeadLetterEntryBuilder b)]) =
      _$DeadLetterEntry;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(DeadLetterEntryBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<DeadLetterEntry> get serializer =>
      _$DeadLetterEntrySerializer();
}

class _$DeadLetterEntrySerializer
    implements PrimitiveSerializer<DeadLetterEntry> {
  @override
  final Iterable<Type> types = const [DeadLetterEntry, _$DeadLetterEntry];

  @override
  final String wireName = r'DeadLetterEntry';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    DeadLetterEntry object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'attempts';
    yield serializers.serialize(
      object.attempts,
      specifiedType: const FullType(int),
    );
    if (object.constraintName != null) {
      yield r'constraint_name';
      yield serializers.serialize(
        object.constraintName,
        specifiedType: const FullType.nullable(String),
      );
    }
    yield r'error_message';
    yield serializers.serialize(
      object.errorMessage,
      specifiedType: const FullType(String),
    );
    yield r'event_name';
    yield serializers.serialize(
      object.eventName,
      specifiedType: const FullType(String),
    );
    yield r'first_seen_at';
    yield serializers.serialize(
      object.firstSeenAt,
      specifiedType: const FullType(DateTime),
    );
    yield r'last_seen_at';
    yield serializers.serialize(
      object.lastSeenAt,
      specifiedType: const FullType(DateTime),
    );
    yield r'partition_id';
    yield serializers.serialize(
      object.partitionId,
      specifiedType: const FullType(int),
    );
    yield r'projection_id';
    yield serializers.serialize(
      object.projectionId,
      specifiedType: const FullType(String),
    );
    yield r'sequence';
    yield serializers.serialize(
      object.sequence,
      specifiedType: const FullType(int),
    );
    if (object.sqlstate != null) {
      yield r'sqlstate';
      yield serializers.serialize(
        object.sqlstate,
        specifiedType: const FullType.nullable(String),
      );
    }
    yield r'stream_id';
    yield serializers.serialize(
      object.streamId,
      specifiedType: const FullType(String),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    DeadLetterEntry object, {
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
    required DeadLetterEntryBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'attempts':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.attempts = valueDes;
          break;
        case r'constraint_name':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.constraintName = valueDes;
          break;
        case r'error_message':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.errorMessage = valueDes;
          break;
        case r'event_name':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.eventName = valueDes;
          break;
        case r'first_seen_at':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.firstSeenAt = valueDes;
          break;
        case r'last_seen_at':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.lastSeenAt = valueDes;
          break;
        case r'partition_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.partitionId = valueDes;
          break;
        case r'projection_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.projectionId = valueDes;
          break;
        case r'sequence':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.sequence = valueDes;
          break;
        case r'sqlstate':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.sqlstate = valueDes;
          break;
        case r'stream_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.streamId = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  DeadLetterEntry deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = DeadLetterEntryBuilder();
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
