// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:breakdown_api/src/model/apply_state.dart';
import 'package:breakdown_api/src/model/apply_run_outcome.dart';
import 'package:breakdown_api/src/model/apply_progress.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'apply_progress_frame.g.dart';

/// Wire payload of one apply-progress frame (issue #762).  Deliberately narrower than [`AiImportJob`]: the apply does not change the job row's status, so a client watching an apply needs the run's own numbers and nothing else. `apply_progress: None` is the run's **end** signal.  Since issue #899 the frame also carries the run slot's own state and — once the run is over — its **persisted outcome**, so a stream that the client attaches to *after* the run finished still learns what committed instead of only learning that nothing is running any more (design D4).
///
/// Properties:
/// * [applyProgress]
/// * [applyResult] - The persisted outcome of the last finished run, `None` while none has finished. Additive with `serde(default)`.
/// * [applyState] - Lifecycle state of the job's apply slot at the moment of this frame (issue #899). Additive with `serde(default)`: a pre-#899 frame decodes as [`ApplyState::Idle`], which is exactly what such a frame described.
/// * [jobId] - Opaque identifier for an operational AI import job.
/// * [runId] - The identity of the run this frame describes (issue #899), `None` when the slot has no owner. `apply_progress` carries the same id while a run is publishing, but the **terminal** frame has no progress payload — so without this field a client could not attribute the outcome it just received to the run it dispatched.
@BuiltValue()
abstract class ApplyProgressFrame
    implements Built<ApplyProgressFrame, ApplyProgressFrameBuilder> {
  @BuiltValueField(wireName: r'apply_progress')
  ApplyProgress? get applyProgress;

  /// The persisted outcome of the last finished run, `None` while none has finished. Additive with `serde(default)`.
  @BuiltValueField(wireName: r'apply_result')
  ApplyRunOutcome? get applyResult;

  /// Lifecycle state of the job's apply slot at the moment of this frame (issue #899). Additive with `serde(default)`: a pre-#899 frame decodes as [`ApplyState::Idle`], which is exactly what such a frame described.
  @BuiltValueField(wireName: r'apply_state')
  ApplyState? get applyState;
  // enum applyStateEnum {  idle,  requested,  running,  done,  failed,  };

  /// Opaque identifier for an operational AI import job.
  @BuiltValueField(wireName: r'job_id')
  String get jobId;

  /// The identity of the run this frame describes (issue #899), `None` when the slot has no owner. `apply_progress` carries the same id while a run is publishing, but the **terminal** frame has no progress payload — so without this field a client could not attribute the outcome it just received to the run it dispatched.
  @BuiltValueField(wireName: r'run_id')
  String? get runId;

  ApplyProgressFrame._();

  factory ApplyProgressFrame([void updates(ApplyProgressFrameBuilder b)]) =
      _$ApplyProgressFrame;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ApplyProgressFrameBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ApplyProgressFrame> get serializer =>
      _$ApplyProgressFrameSerializer();
}

class _$ApplyProgressFrameSerializer
    implements PrimitiveSerializer<ApplyProgressFrame> {
  @override
  final Iterable<Type> types = const [ApplyProgressFrame, _$ApplyProgressFrame];

  @override
  final String wireName = r'ApplyProgressFrame';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ApplyProgressFrame object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.applyProgress != null) {
      yield r'apply_progress';
      yield serializers.serialize(
        object.applyProgress,
        specifiedType: const FullType.nullable(ApplyProgress),
      );
    }
    if (object.applyResult != null) {
      yield r'apply_result';
      yield serializers.serialize(
        object.applyResult,
        specifiedType: const FullType.nullable(ApplyRunOutcome),
      );
    }
    if (object.applyState != null) {
      yield r'apply_state';
      yield serializers.serialize(
        object.applyState,
        specifiedType: const FullType(ApplyState),
      );
    }
    yield r'job_id';
    yield serializers.serialize(
      object.jobId,
      specifiedType: const FullType(String),
    );
    if (object.runId != null) {
      yield r'run_id';
      yield serializers.serialize(
        object.runId,
        specifiedType: const FullType.nullable(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    ApplyProgressFrame object, {
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
    required ApplyProgressFrameBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'apply_progress':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(ApplyProgress),
          ) as ApplyProgress?;
          if (valueDes == null) continue;
          result.applyProgress.replace(valueDes);
          break;
        case r'apply_result':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(ApplyRunOutcome),
          ) as ApplyRunOutcome?;
          if (valueDes == null) continue;
          result.applyResult.replace(valueDes);
          break;
        case r'apply_state':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(ApplyState),
          ) as ApplyState?;
          if (valueDes == null) continue;
          result.applyState = valueDes;
          break;
        case r'job_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.jobId = valueDes;
          break;
        case r'run_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.runId = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  ApplyProgressFrame deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ApplyProgressFrameBuilder();
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
