// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:breakdown_api/src/model/apply_stage.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'apply_progress.g.dart';

/// Live progress of one apply run (issue #762).  The apply used to be a pure spinner: `POST /ai-import/jobs/{id}/apply` resolves the plan and awaits `ApplyWorker::apply_script` over every mapping, so a 57-row preview and a 4-row preview looked identical for however many minutes they took.  Written by the apply worker from the plan it already holds (never from a projection read) and cleared when the run ends — including on failure — so the client's stream closes on a definite event rather than on a timeout.
///
/// Properties:
/// * [applied] - Work units completed by **this** run (rows dispatched).
/// * [stage]
/// * [startedAt] - When this run started: the anchor an ETA needs (the same role [`AiImportProgress::started_at`] plays for extraction).
/// * [total] - Work units the run planned (the plan's row count). `0` is an honest state — an empty plan still runs its trailing work — and never a divisor the client may trust blindly.
/// * [updatedAt] - Last write of this payload. The stream uses it to recognise a run whose process died: an abandoned run must not keep a stream open forever, so a payload older than [`ApplyProgress::STALE_AFTER`] is treated as finished.
@BuiltValue()
abstract class ApplyProgress
    implements Built<ApplyProgress, ApplyProgressBuilder> {
  /// Work units completed by **this** run (rows dispatched).
  @BuiltValueField(wireName: r'applied')
  int? get applied;

  @BuiltValueField(wireName: r'stage')
  ApplyStage get stage;
  // enum stageEnum {  applying,  finalizing,  };

  /// When this run started: the anchor an ETA needs (the same role [`AiImportProgress::started_at`] plays for extraction).
  @BuiltValueField(wireName: r'started_at')
  DateTime get startedAt;

  /// Work units the run planned (the plan's row count). `0` is an honest state — an empty plan still runs its trailing work — and never a divisor the client may trust blindly.
  @BuiltValueField(wireName: r'total')
  int? get total;

  /// Last write of this payload. The stream uses it to recognise a run whose process died: an abandoned run must not keep a stream open forever, so a payload older than [`ApplyProgress::STALE_AFTER`] is treated as finished.
  @BuiltValueField(wireName: r'updated_at')
  DateTime get updatedAt;

  ApplyProgress._();

  factory ApplyProgress([void updates(ApplyProgressBuilder b)]) =
      _$ApplyProgress;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ApplyProgressBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ApplyProgress> get serializer =>
      _$ApplyProgressSerializer();
}

class _$ApplyProgressSerializer implements PrimitiveSerializer<ApplyProgress> {
  @override
  final Iterable<Type> types = const [ApplyProgress, _$ApplyProgress];

  @override
  final String wireName = r'ApplyProgress';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ApplyProgress object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.applied != null) {
      yield r'applied';
      yield serializers.serialize(
        object.applied,
        specifiedType: const FullType(int),
      );
    }
    yield r'stage';
    yield serializers.serialize(
      object.stage,
      specifiedType: const FullType(ApplyStage),
    );
    yield r'started_at';
    yield serializers.serialize(
      object.startedAt,
      specifiedType: const FullType(DateTime),
    );
    if (object.total != null) {
      yield r'total';
      yield serializers.serialize(
        object.total,
        specifiedType: const FullType(int),
      );
    }
    yield r'updated_at';
    yield serializers.serialize(
      object.updatedAt,
      specifiedType: const FullType(DateTime),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    ApplyProgress object, {
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
    required ApplyProgressBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'applied':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(int),
          ) as int?;
          if (valueDes == null) continue;
          result.applied = valueDes;
          break;
        case r'stage':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(ApplyStage),
          ) as ApplyStage;
          result.stage = valueDes;
          break;
        case r'started_at':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.startedAt = valueDes;
          break;
        case r'total':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(int),
          ) as int?;
          if (valueDes == null) continue;
          result.total = valueDes;
          break;
        case r'updated_at':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.updatedAt = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  ApplyProgress deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ApplyProgressBuilder();
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
