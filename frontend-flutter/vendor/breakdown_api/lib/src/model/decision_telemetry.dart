// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:breakdown_api/src/model/llm_provider.dart';
import 'package:breakdown_api/src/model/decision_outcome.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'decision_telemetry.g.dart';

/// What the Decision Model scoring pass did for one import job (issue #767).  Server-derived truth, written by the worker in the same completion write as the extraction telemetry (owner-fenced) — never inferred by a client and never fabricated when the pass could not run.
///
/// Properties:
/// * [failedRows] - Preview rows whose own scoring request failed (their rubric carries `scoring_failed`). `0` unless the outcome is [`DecisionOutcome::ScoringFailed`]; a partially failed chunk leaves the successful rows scored and only counts the failures.
/// * [model] - The decision model id the job resolved for scoring. Same presence rules as [`Self::provider`].
/// * [outcome]
/// * [provider] - The provider the job *resolved* for scoring. `Some` for every outcome except [`DecisionOutcome::SkippedNoConfig`] and [`DecisionOutcome::SkippedNotApplicable`] — a job whose configuration named a provider names it here even when the client could not be built, so \"did my config reach the worker?\" is answerable after the fact.
@BuiltValue()
abstract class DecisionTelemetry
    implements Built<DecisionTelemetry, DecisionTelemetryBuilder> {
  /// Preview rows whose own scoring request failed (their rubric carries `scoring_failed`). `0` unless the outcome is [`DecisionOutcome::ScoringFailed`]; a partially failed chunk leaves the successful rows scored and only counts the failures.
  @BuiltValueField(wireName: r'failed_rows')
  int? get failedRows;

  /// The decision model id the job resolved for scoring. Same presence rules as [`Self::provider`].
  @BuiltValueField(wireName: r'model')
  String? get model;

  @BuiltValueField(wireName: r'outcome')
  DecisionOutcome get outcome;
  // enum outcomeEnum {  ran,  skipped_no_config,  client_unavailable,  scoring_failed,  skipped_not_applicable,  };

  /// The provider the job *resolved* for scoring. `Some` for every outcome except [`DecisionOutcome::SkippedNoConfig`] and [`DecisionOutcome::SkippedNotApplicable`] — a job whose configuration named a provider names it here even when the client could not be built, so \"did my config reach the worker?\" is answerable after the fact.
  @BuiltValueField(wireName: r'provider')
  LlmProvider? get provider;
  // enum providerEnum {  openai,  gemini,  openrouter,  eurouter,  neuralwatt,  opencode-go,  opencode,  ollama,  };

  DecisionTelemetry._();

  factory DecisionTelemetry([void updates(DecisionTelemetryBuilder b)]) =
      _$DecisionTelemetry;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(DecisionTelemetryBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<DecisionTelemetry> get serializer =>
      _$DecisionTelemetrySerializer();
}

class _$DecisionTelemetrySerializer
    implements PrimitiveSerializer<DecisionTelemetry> {
  @override
  final Iterable<Type> types = const [DecisionTelemetry, _$DecisionTelemetry];

  @override
  final String wireName = r'DecisionTelemetry';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    DecisionTelemetry object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.failedRows != null) {
      yield r'failed_rows';
      yield serializers.serialize(
        object.failedRows,
        specifiedType: const FullType(int),
      );
    }
    if (object.model != null) {
      yield r'model';
      yield serializers.serialize(
        object.model,
        specifiedType: const FullType.nullable(String),
      );
    }
    yield r'outcome';
    yield serializers.serialize(
      object.outcome,
      specifiedType: const FullType(DecisionOutcome),
    );
    if (object.provider != null) {
      yield r'provider';
      yield serializers.serialize(
        object.provider,
        specifiedType: const FullType.nullable(LlmProvider),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    DecisionTelemetry object, {
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
    required DecisionTelemetryBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'failed_rows':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(int),
          ) as int?;
          if (valueDes == null) continue;
          result.failedRows = valueDes;
          break;
        case r'model':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.model = valueDes;
          break;
        case r'outcome':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DecisionOutcome),
          ) as DecisionOutcome;
          result.outcome = valueDes;
          break;
        case r'provider':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(LlmProvider),
          ) as LlmProvider?;
          if (valueDes == null) continue;
          result.provider = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  DecisionTelemetry deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = DecisionTelemetryBuilder();
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
