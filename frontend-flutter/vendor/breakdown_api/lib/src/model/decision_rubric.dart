// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:breakdown_api/src/model/llm_provider.dart';
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'decision_rubric.g.dart';

/// Structured rubric sub-scores persisted on the preview payload (issue #722: \"persist structured rubric sub-scores … to prepare the 0.5.x automatic prompt optimization loop\"). Additive with `serde(default)` so previews stored before this field existed still deserialize.
///
/// Properties:
/// * [decisionModel] - Decision model that produced the sub-scores.
/// * [decisionProvider] - Decision provider that produced the sub-scores.
/// * [groundingFactor] - The deterministic grounding signals blended into the scores.
/// * [scoringFailed] - Whether the decision endpoint failed for this unit (telemetry only — the scores degraded to `None` either way). Omitted when `false`.
/// * [subScores] - Calibrated sub-question probabilities keyed by [`question_keys`] names — the APO reward-signal foundation.
@BuiltValue()
abstract class DecisionRubric
    implements Built<DecisionRubric, DecisionRubricBuilder> {
  /// Decision model that produced the sub-scores.
  @BuiltValueField(wireName: r'decision_model')
  String? get decisionModel;

  /// Decision provider that produced the sub-scores.
  @BuiltValueField(wireName: r'decision_provider')
  LlmProvider? get decisionProvider;
  // enum decisionProviderEnum {  openai,  gemini,  openrouter,  eurouter,  neuralwatt,  opencode-go,  opencode,  ollama,  };

  /// The deterministic grounding signals blended into the scores.
  @BuiltValueField(wireName: r'grounding_factor')
  double? get groundingFactor;

  /// Whether the decision endpoint failed for this unit (telemetry only — the scores degraded to `None` either way). Omitted when `false`.
  @BuiltValueField(wireName: r'scoring_failed')
  bool? get scoringFailed;

  /// Calibrated sub-question probabilities keyed by [`question_keys`] names — the APO reward-signal foundation.
  @BuiltValueField(wireName: r'sub_scores')
  BuiltMap<String, double>? get subScores;

  DecisionRubric._();

  factory DecisionRubric([void updates(DecisionRubricBuilder b)]) =
      _$DecisionRubric;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(DecisionRubricBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<DecisionRubric> get serializer =>
      _$DecisionRubricSerializer();
}

class _$DecisionRubricSerializer
    implements PrimitiveSerializer<DecisionRubric> {
  @override
  final Iterable<Type> types = const [DecisionRubric, _$DecisionRubric];

  @override
  final String wireName = r'DecisionRubric';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    DecisionRubric object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.decisionModel != null) {
      yield r'decision_model';
      yield serializers.serialize(
        object.decisionModel,
        specifiedType: const FullType.nullable(String),
      );
    }
    if (object.decisionProvider != null) {
      yield r'decision_provider';
      yield serializers.serialize(
        object.decisionProvider,
        specifiedType: const FullType.nullable(LlmProvider),
      );
    }
    if (object.groundingFactor != null) {
      yield r'grounding_factor';
      yield serializers.serialize(
        object.groundingFactor,
        specifiedType: const FullType.nullable(double),
      );
    }
    if (object.scoringFailed != null) {
      yield r'scoring_failed';
      yield serializers.serialize(
        object.scoringFailed,
        specifiedType: const FullType(bool),
      );
    }
    if (object.subScores != null) {
      yield r'sub_scores';
      yield serializers.serialize(
        object.subScores,
        specifiedType:
            const FullType(BuiltMap, [FullType(String), FullType(double)]),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    DecisionRubric object, {
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
    required DecisionRubricBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'decision_model':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.decisionModel = valueDes;
          break;
        case r'decision_provider':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(LlmProvider),
          ) as LlmProvider?;
          if (valueDes == null) continue;
          result.decisionProvider = valueDes;
          break;
        case r'grounding_factor':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(double),
          ) as double?;
          if (valueDes == null) continue;
          result.groundingFactor = valueDes;
          break;
        case r'scoring_failed':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(bool),
          ) as bool?;
          if (valueDes == null) continue;
          result.scoringFailed = valueDes;
          break;
        case r'sub_scores':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(
                BuiltMap, [FullType(String), FullType(double)]),
          ) as BuiltMap<String, double>?;
          if (valueDes == null) continue;
          result.subScores.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  DecisionRubric deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = DecisionRubricBuilder();
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
