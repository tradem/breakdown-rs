// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:breakdown_api/src/model/llm_provider.dart';
import 'package:built_collection/built_collection.dart';
import 'package:breakdown_api/src/model/reasoning_effort.dart';
import 'package:breakdown_api/src/model/model_pricing.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'model_info.g.dart';

/// ModelInfo
///
/// Properties:
/// * [displayName]
/// * [id]
/// * [pricing] - Pricing snapshot from the `ai_import.ai_model_pricing` read model (issue #675). `None` for models without known pricing (e.g. local Ollama models) — never a fabricated zero-price object. Additive with `serde(default)` on the wire.
/// * [provider]
/// * [recommended] - Whether the curated catalog designates this model as the provider's recommended default for a new AI-config creation (issue #471). Only set by the curated models endpoint (`curated_models`); models fetched live from a provider never carry the flag (`false`).  `#[serde(default)]`: the flag is additive on the wire — a backend that predates the field deserializes it as `false`, so clients keep their \"first model\" fallback for pre-flag deployments (CodeRabbit review, PR #489).
/// * [supportedReasoningEfforts] - Every `reasoning_effort` this model DECLARES, empty when it declares none (2026-11-20 output-budget investigation).  Carried on the model list so a client can offer exactly the levels the selected pair accepts instead of discovering a `400` at import time — which is why the picker has to react to the model selection, not to one global list. Additive with `serde(default)`: a backend that predates the field (or a live provider catalogue we cannot read) yields an empty list, i.e. \"no choosable level\", never a guessed one.
@BuiltValue()
abstract class ModelInfo implements Built<ModelInfo, ModelInfoBuilder> {
  @BuiltValueField(wireName: r'display_name')
  String? get displayName;

  @BuiltValueField(wireName: r'id')
  String get id;

  /// Pricing snapshot from the `ai_import.ai_model_pricing` read model (issue #675). `None` for models without known pricing (e.g. local Ollama models) — never a fabricated zero-price object. Additive with `serde(default)` on the wire.
  @BuiltValueField(wireName: r'pricing')
  ModelPricing? get pricing;

  @BuiltValueField(wireName: r'provider')
  LlmProvider get provider;
  // enum providerEnum {  openai,  gemini,  openrouter,  eurouter,  neuralwatt,  opencode-go,  opencode,  ollama,  };

  /// Whether the curated catalog designates this model as the provider's recommended default for a new AI-config creation (issue #471). Only set by the curated models endpoint (`curated_models`); models fetched live from a provider never carry the flag (`false`).  `#[serde(default)]`: the flag is additive on the wire — a backend that predates the field deserializes it as `false`, so clients keep their \"first model\" fallback for pre-flag deployments (CodeRabbit review, PR #489).
  @BuiltValueField(wireName: r'recommended')
  bool? get recommended;

  /// Every `reasoning_effort` this model DECLARES, empty when it declares none (2026-11-20 output-budget investigation).  Carried on the model list so a client can offer exactly the levels the selected pair accepts instead of discovering a `400` at import time — which is why the picker has to react to the model selection, not to one global list. Additive with `serde(default)`: a backend that predates the field (or a live provider catalogue we cannot read) yields an empty list, i.e. \"no choosable level\", never a guessed one.
  @BuiltValueField(wireName: r'supported_reasoning_efforts')
  BuiltList<ReasoningEffort>? get supportedReasoningEfforts;

  ModelInfo._();

  factory ModelInfo([void updates(ModelInfoBuilder b)]) = _$ModelInfo;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ModelInfoBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ModelInfo> get serializer => _$ModelInfoSerializer();
}

class _$ModelInfoSerializer implements PrimitiveSerializer<ModelInfo> {
  @override
  final Iterable<Type> types = const [ModelInfo, _$ModelInfo];

  @override
  final String wireName = r'ModelInfo';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ModelInfo object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.displayName != null) {
      yield r'display_name';
      yield serializers.serialize(
        object.displayName,
        specifiedType: const FullType.nullable(String),
      );
    }
    yield r'id';
    yield serializers.serialize(
      object.id,
      specifiedType: const FullType(String),
    );
    if (object.pricing != null) {
      yield r'pricing';
      yield serializers.serialize(
        object.pricing,
        specifiedType: const FullType.nullable(ModelPricing),
      );
    }
    yield r'provider';
    yield serializers.serialize(
      object.provider,
      specifiedType: const FullType(LlmProvider),
    );
    if (object.recommended != null) {
      yield r'recommended';
      yield serializers.serialize(
        object.recommended,
        specifiedType: const FullType(bool),
      );
    }
    if (object.supportedReasoningEfforts != null) {
      yield r'supported_reasoning_efforts';
      yield serializers.serialize(
        object.supportedReasoningEfforts,
        specifiedType: const FullType(BuiltList, [FullType(ReasoningEffort)]),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    ModelInfo object, {
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
    required ModelInfoBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'display_name':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.displayName = valueDes;
          break;
        case r'id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.id = valueDes;
          break;
        case r'pricing':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(ModelPricing),
          ) as ModelPricing?;
          if (valueDes == null) continue;
          result.pricing.replace(valueDes);
          break;
        case r'provider':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(LlmProvider),
          ) as LlmProvider;
          result.provider = valueDes;
          break;
        case r'recommended':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(bool),
          ) as bool?;
          if (valueDes == null) continue;
          result.recommended = valueDes;
          break;
        case r'supported_reasoning_efforts':
          final valueDes = serializers.deserialize(
            value,
            specifiedType:
                const FullType.nullable(BuiltList, [FullType(ReasoningEffort)]),
          ) as BuiltList<ReasoningEffort>?;
          if (valueDes == null) continue;
          result.supportedReasoningEfforts.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  ModelInfo deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ModelInfoBuilder();
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
