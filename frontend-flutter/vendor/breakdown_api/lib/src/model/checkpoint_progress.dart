// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'checkpoint_progress.g.dart';

/// Checkpoint progress of one partition of one projection.  Wire shape of `GET /v1/ops/projector-health` → `checkpoints`.
///
/// Properties:
/// * [partitionId] - SierraDB partition the projection's event streams hash into.
/// * [projectionId] - Checkpoint projection id (the aggregate category, e.g. `season`).
/// * [sequence] - Last flushed partition sequence (0-based; the projector is caught up through this event).
@BuiltValue()
abstract class CheckpointProgress
    implements Built<CheckpointProgress, CheckpointProgressBuilder> {
  /// SierraDB partition the projection's event streams hash into.
  @BuiltValueField(wireName: r'partition_id')
  int get partitionId;

  /// Checkpoint projection id (the aggregate category, e.g. `season`).
  @BuiltValueField(wireName: r'projection_id')
  String get projectionId;

  /// Last flushed partition sequence (0-based; the projector is caught up through this event).
  @BuiltValueField(wireName: r'sequence')
  int get sequence;

  CheckpointProgress._();

  factory CheckpointProgress([void updates(CheckpointProgressBuilder b)]) =
      _$CheckpointProgress;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(CheckpointProgressBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<CheckpointProgress> get serializer =>
      _$CheckpointProgressSerializer();
}

class _$CheckpointProgressSerializer
    implements PrimitiveSerializer<CheckpointProgress> {
  @override
  final Iterable<Type> types = const [CheckpointProgress, _$CheckpointProgress];

  @override
  final String wireName = r'CheckpointProgress';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    CheckpointProgress object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
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
  }

  @override
  Object serialize(
    Serializers serializers,
    CheckpointProgress object, {
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
    required CheckpointProgressBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
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
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  CheckpointProgress deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = CheckpointProgressBuilder();
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
