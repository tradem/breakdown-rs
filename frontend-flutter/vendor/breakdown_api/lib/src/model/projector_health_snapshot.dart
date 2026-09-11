// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:breakdown_api/src/model/dead_letter_entry.dart';
import 'package:breakdown_api/src/model/checkpoint_progress.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'projector_health_snapshot.g.dart';

/// Aggregate response of the projector-health read (issue #409).
///
/// Properties:
/// * [checkpoints] - Checkpoint progress of every partition of every projection — the \"is the projector advancing?\" signal.
/// * [deadLetterCount] - Number of distinct poison events currently dead-lettered.
/// * [deadLetters] - Latest dead-letter entries, most recently seen first (bounded by the request's `limit`).
@BuiltValue()
abstract class ProjectorHealthSnapshot
    implements Built<ProjectorHealthSnapshot, ProjectorHealthSnapshotBuilder> {
  /// Checkpoint progress of every partition of every projection — the \"is the projector advancing?\" signal.
  @BuiltValueField(wireName: r'checkpoints')
  BuiltList<CheckpointProgress> get checkpoints;

  /// Number of distinct poison events currently dead-lettered.
  @BuiltValueField(wireName: r'dead_letter_count')
  int get deadLetterCount;

  /// Latest dead-letter entries, most recently seen first (bounded by the request's `limit`).
  @BuiltValueField(wireName: r'dead_letters')
  BuiltList<DeadLetterEntry> get deadLetters;

  ProjectorHealthSnapshot._();

  factory ProjectorHealthSnapshot(
          [void updates(ProjectorHealthSnapshotBuilder b)]) =
      _$ProjectorHealthSnapshot;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ProjectorHealthSnapshotBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ProjectorHealthSnapshot> get serializer =>
      _$ProjectorHealthSnapshotSerializer();
}

class _$ProjectorHealthSnapshotSerializer
    implements PrimitiveSerializer<ProjectorHealthSnapshot> {
  @override
  final Iterable<Type> types = const [
    ProjectorHealthSnapshot,
    _$ProjectorHealthSnapshot
  ];

  @override
  final String wireName = r'ProjectorHealthSnapshot';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ProjectorHealthSnapshot object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'checkpoints';
    yield serializers.serialize(
      object.checkpoints,
      specifiedType: const FullType(BuiltList, [FullType(CheckpointProgress)]),
    );
    yield r'dead_letter_count';
    yield serializers.serialize(
      object.deadLetterCount,
      specifiedType: const FullType(int),
    );
    yield r'dead_letters';
    yield serializers.serialize(
      object.deadLetters,
      specifiedType: const FullType(BuiltList, [FullType(DeadLetterEntry)]),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    ProjectorHealthSnapshot object, {
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
    required ProjectorHealthSnapshotBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'checkpoints':
          final valueDes = serializers.deserialize(
            value,
            specifiedType:
                const FullType(BuiltList, [FullType(CheckpointProgress)]),
          ) as BuiltList<CheckpointProgress>;
          result.checkpoints.replace(valueDes);
          break;
        case r'dead_letter_count':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.deadLetterCount = valueDes;
          break;
        case r'dead_letters':
          final valueDes = serializers.deserialize(
            value,
            specifiedType:
                const FullType(BuiltList, [FullType(DeadLetterEntry)]),
          ) as BuiltList<DeadLetterEntry>;
          result.deadLetters.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  ProjectorHealthSnapshot deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ProjectorHealthSnapshotBuilder();
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
