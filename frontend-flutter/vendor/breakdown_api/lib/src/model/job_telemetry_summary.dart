// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:breakdown_api/src/model/document_kind.dart';
import 'package:breakdown_api/src/model/llm_provider.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'job_telemetry_summary.g.dart';

/// Telemetry summary as exposed on the `AiImportJob` wire view (issue #675). `None` until the worker records telemetry; additive on the wire.
///
/// Properties:
/// * [cachedTokensIn]
/// * [chunkCount]
/// * [docKind]
/// * [energyMillijoules]
/// * [latencyTotalMs]
/// * [model]
/// * [provider]
/// * [scenesDetected] - Scene headings the deterministic scan detected (issue #758): the count the *document* states, as opposed to the preview rows the model produced. Additive with `serde(default)`; `0` for schedule jobs.
/// * [scenesExtracted] - Preview rows the extraction model returned (issue #758). A client can explain a short preview by comparing this with `scenes_detected` instead of guessing.
/// * [scenesSynthesized] - Preview rows rebuilt from the deterministic heading because their chunk returned no rows (issue #758). A nonzero value names the degradation.
/// * [tokensIn]
/// * [tokensOut]
@BuiltValue()
abstract class JobTelemetrySummary
    implements Built<JobTelemetrySummary, JobTelemetrySummaryBuilder> {
  @BuiltValueField(wireName: r'cached_tokens_in')
  int get cachedTokensIn;

  @BuiltValueField(wireName: r'chunk_count')
  int get chunkCount;

  @BuiltValueField(wireName: r'doc_kind')
  DocumentKind? get docKind;
  // enum docKindEnum {  script,  schedule,  };

  @BuiltValueField(wireName: r'energy_millijoules')
  int get energyMillijoules;

  @BuiltValueField(wireName: r'latency_total_ms')
  int get latencyTotalMs;

  @BuiltValueField(wireName: r'model')
  String? get model;

  @BuiltValueField(wireName: r'provider')
  LlmProvider? get provider;
  // enum providerEnum {  openai,  gemini,  openrouter,  eurouter,  neuralwatt,  opencode-go,  opencode,  ollama,  };

  /// Scene headings the deterministic scan detected (issue #758): the count the *document* states, as opposed to the preview rows the model produced. Additive with `serde(default)`; `0` for schedule jobs.
  @BuiltValueField(wireName: r'scenes_detected')
  int? get scenesDetected;

  /// Preview rows the extraction model returned (issue #758). A client can explain a short preview by comparing this with `scenes_detected` instead of guessing.
  @BuiltValueField(wireName: r'scenes_extracted')
  int? get scenesExtracted;

  /// Preview rows rebuilt from the deterministic heading because their chunk returned no rows (issue #758). A nonzero value names the degradation.
  @BuiltValueField(wireName: r'scenes_synthesized')
  int? get scenesSynthesized;

  @BuiltValueField(wireName: r'tokens_in')
  int get tokensIn;

  @BuiltValueField(wireName: r'tokens_out')
  int get tokensOut;

  JobTelemetrySummary._();

  factory JobTelemetrySummary([void updates(JobTelemetrySummaryBuilder b)]) =
      _$JobTelemetrySummary;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(JobTelemetrySummaryBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<JobTelemetrySummary> get serializer =>
      _$JobTelemetrySummarySerializer();
}

class _$JobTelemetrySummarySerializer
    implements PrimitiveSerializer<JobTelemetrySummary> {
  @override
  final Iterable<Type> types = const [
    JobTelemetrySummary,
    _$JobTelemetrySummary
  ];

  @override
  final String wireName = r'JobTelemetrySummary';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    JobTelemetrySummary object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'cached_tokens_in';
    yield serializers.serialize(
      object.cachedTokensIn,
      specifiedType: const FullType(int),
    );
    yield r'chunk_count';
    yield serializers.serialize(
      object.chunkCount,
      specifiedType: const FullType(int),
    );
    if (object.docKind != null) {
      yield r'doc_kind';
      yield serializers.serialize(
        object.docKind,
        specifiedType: const FullType.nullable(DocumentKind),
      );
    }
    yield r'energy_millijoules';
    yield serializers.serialize(
      object.energyMillijoules,
      specifiedType: const FullType(int),
    );
    yield r'latency_total_ms';
    yield serializers.serialize(
      object.latencyTotalMs,
      specifiedType: const FullType(int),
    );
    if (object.model != null) {
      yield r'model';
      yield serializers.serialize(
        object.model,
        specifiedType: const FullType.nullable(String),
      );
    }
    if (object.provider != null) {
      yield r'provider';
      yield serializers.serialize(
        object.provider,
        specifiedType: const FullType.nullable(LlmProvider),
      );
    }
    if (object.scenesDetected != null) {
      yield r'scenes_detected';
      yield serializers.serialize(
        object.scenesDetected,
        specifiedType: const FullType(int),
      );
    }
    if (object.scenesExtracted != null) {
      yield r'scenes_extracted';
      yield serializers.serialize(
        object.scenesExtracted,
        specifiedType: const FullType(int),
      );
    }
    if (object.scenesSynthesized != null) {
      yield r'scenes_synthesized';
      yield serializers.serialize(
        object.scenesSynthesized,
        specifiedType: const FullType(int),
      );
    }
    yield r'tokens_in';
    yield serializers.serialize(
      object.tokensIn,
      specifiedType: const FullType(int),
    );
    yield r'tokens_out';
    yield serializers.serialize(
      object.tokensOut,
      specifiedType: const FullType(int),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    JobTelemetrySummary object, {
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
    required JobTelemetrySummaryBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'cached_tokens_in':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.cachedTokensIn = valueDes;
          break;
        case r'chunk_count':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.chunkCount = valueDes;
          break;
        case r'doc_kind':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(DocumentKind),
          ) as DocumentKind?;
          if (valueDes == null) continue;
          result.docKind = valueDes;
          break;
        case r'energy_millijoules':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.energyMillijoules = valueDes;
          break;
        case r'latency_total_ms':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.latencyTotalMs = valueDes;
          break;
        case r'model':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.model = valueDes;
          break;
        case r'provider':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(LlmProvider),
          ) as LlmProvider?;
          if (valueDes == null) continue;
          result.provider = valueDes;
          break;
        case r'scenes_detected':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(int),
          ) as int?;
          if (valueDes == null) continue;
          result.scenesDetected = valueDes;
          break;
        case r'scenes_extracted':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(int),
          ) as int?;
          if (valueDes == null) continue;
          result.scenesExtracted = valueDes;
          break;
        case r'scenes_synthesized':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(int),
          ) as int?;
          if (valueDes == null) continue;
          result.scenesSynthesized = valueDes;
          break;
        case r'tokens_in':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.tokensIn = valueDes;
          break;
        case r'tokens_out':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.tokensOut = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  JobTelemetrySummary deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = JobTelemetrySummaryBuilder();
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
