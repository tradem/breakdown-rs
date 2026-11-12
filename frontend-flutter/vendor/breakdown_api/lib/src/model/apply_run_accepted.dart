// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:breakdown_api/src/model/apply_state.dart';
import 'package:breakdown_api/src/model/apply_stage.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'apply_run_accepted.g.dart';

/// The `202 Accepted` body of `POST /ai-import/jobs/{id}/apply` (issue #899, design D2).  The request no longer performs the apply: it validates, claims the run slot and dispatches. The counters arrive later — on the apply stream's terminal frame and on `GET /ai-import/jobs/{id}` — because the run must outlive the connection that started it.
///
/// Properties:
/// * [applyState] - The slot state at the moment of the answer (always [`ApplyState::Requested`]). Explicit rather than implied, so a client reads the re-entry state machine off one shape.
/// * [runId] - The identity of the run the slot now owns. Every progress frame of this run carries it, so a client can tell \"my run\" from a later one.
/// * [stage] - The run's stage at dispatch time (always `applying`; it exists so the descriptor stays additive if a later stage becomes dispatchable).
/// * [startedAt] - When the run was claimed — the anchor the client renders and the value a re-attaching client compares against the frames it receives.
@BuiltValue()
abstract class ApplyRunAccepted
    implements Built<ApplyRunAccepted, ApplyRunAcceptedBuilder> {
  /// The slot state at the moment of the answer (always [`ApplyState::Requested`]). Explicit rather than implied, so a client reads the re-entry state machine off one shape.
  @BuiltValueField(wireName: r'apply_state')
  ApplyState get applyState;
  // enum applyStateEnum {  idle,  requested,  running,  done,  failed,  };

  /// The identity of the run the slot now owns. Every progress frame of this run carries it, so a client can tell \"my run\" from a later one.
  @BuiltValueField(wireName: r'run_id')
  String get runId;

  /// The run's stage at dispatch time (always `applying`; it exists so the descriptor stays additive if a later stage becomes dispatchable).
  @BuiltValueField(wireName: r'stage')
  ApplyStage get stage;
  // enum stageEnum {  applying,  finalizing,  };

  /// When the run was claimed — the anchor the client renders and the value a re-attaching client compares against the frames it receives.
  @BuiltValueField(wireName: r'started_at')
  DateTime get startedAt;

  ApplyRunAccepted._();

  factory ApplyRunAccepted([void updates(ApplyRunAcceptedBuilder b)]) =
      _$ApplyRunAccepted;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ApplyRunAcceptedBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ApplyRunAccepted> get serializer =>
      _$ApplyRunAcceptedSerializer();
}

class _$ApplyRunAcceptedSerializer
    implements PrimitiveSerializer<ApplyRunAccepted> {
  @override
  final Iterable<Type> types = const [ApplyRunAccepted, _$ApplyRunAccepted];

  @override
  final String wireName = r'ApplyRunAccepted';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ApplyRunAccepted object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'apply_state';
    yield serializers.serialize(
      object.applyState,
      specifiedType: const FullType(ApplyState),
    );
    yield r'run_id';
    yield serializers.serialize(
      object.runId,
      specifiedType: const FullType(String),
    );
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
  }

  @override
  Object serialize(
    Serializers serializers,
    ApplyRunAccepted object, {
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
    required ApplyRunAcceptedBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'apply_state':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(ApplyState),
          ) as ApplyState;
          result.applyState = valueDes;
          break;
        case r'run_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.runId = valueDes;
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
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  ApplyRunAccepted deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ApplyRunAcceptedBuilder();
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
