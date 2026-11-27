// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:breakdown_api/src/model/llm_provider.dart';
import 'package:built_collection/built_collection.dart';
import 'package:breakdown_api/src/model/cost_display_preference.dart';
import 'package:breakdown_api/src/model/reasoning_effort_choice.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'create_ai_config_request.g.dart';

/// CreateAiConfigRequest
///
/// Properties:
/// * [assistantModel]
/// * [costDisplayPreference] - Preferred primary cost display metric (issue #675). Defaults to `token` for clients predating the field.
/// * [decisionModel]
/// * [decisionProvider] - Optional Decision Model slot (issue #722). `decision_vault_key_id` MAY equal `vault_key_id` when `decision_provider == provider` (same-key reuse) or reference a distinct active credential of the decision provider owned by the caller (split billing).
/// * [decisionVaultKeyId]
/// * [imageModel]
/// * [prompts]
/// * [provider]
/// * [reasoningEffort] - Requested `reasoning_effort` for the assistant model (2026-11-20 investigation). `auto` = no explicit level. Only a pair that DECLARES the parameter may name a level — the aggregate answers `422` otherwise, while the mistake is still cheap.
/// * [vaultKeyId]
/// * [visionModel]
/// * [visionProvider] - Optional Vision slot (issue #1013): the provider/model/credential that carries PAGE IMAGES (page-streaming schedules and the VLM structural zoning pass). Unset = \"use the assistant pair\", i.e. exactly the behaviour of a configuration written before the slot existed.  `vision_vault_key_id` MAY equal `vault_key_id` when `vision_provider == provider` (same-key reuse) or reference a distinct active credential of the vision provider owned by the caller.
/// * [visionVaultKeyId]
/// * [visionZdrAttested] - Operator attestation that the VISION provider ACCOUNT has zero data retention enabled (issue #968 semantics, vision-scoped). Separate from `zdr_attested` because it describes a different account as soon as the vision provider differs from the extraction provider. A vision provider that cannot carry page images is refused at save time (`422` `ai-config.vision-provider-unsupported`), never on the first paid page.
/// * [zdrAttested] - Operator attestation that this provider ACCOUNT has zero data retention enabled (issue #968, ADR-041 `D2`). Required to let a provider whose ZDR guarantee is an account switch (Nebius) carry page images; every other provider is unaffected by the flag. Defaults to `false` — an unattested account keeps the vision egress gate fail-closed.
@BuiltValue()
abstract class CreateAiConfigRequest
    implements Built<CreateAiConfigRequest, CreateAiConfigRequestBuilder> {
  @BuiltValueField(wireName: r'assistant_model')
  String get assistantModel;

  /// Preferred primary cost display metric (issue #675). Defaults to `token` for clients predating the field.
  @BuiltValueField(wireName: r'cost_display_preference')
  CostDisplayPreference? get costDisplayPreference;
  // enum costDisplayPreferenceEnum {  token,  energy,  };

  @BuiltValueField(wireName: r'decision_model')
  String? get decisionModel;

  /// Optional Decision Model slot (issue #722). `decision_vault_key_id` MAY equal `vault_key_id` when `decision_provider == provider` (same-key reuse) or reference a distinct active credential of the decision provider owned by the caller (split billing).
  @BuiltValueField(wireName: r'decision_provider')
  LlmProvider? get decisionProvider;
  // enum decisionProviderEnum {  openai,  gemini,  openrouter,  eurouter,  scaleway,  ovhcloud,  nebius,  neuralwatt,  opencode-go,  opencode,  ollama,  };

  @BuiltValueField(wireName: r'decision_vault_key_id')
  String? get decisionVaultKeyId;

  @BuiltValueField(wireName: r'image_model')
  String? get imageModel;

  @BuiltValueField(wireName: r'prompts')
  BuiltMap<String, String> get prompts;

  @BuiltValueField(wireName: r'provider')
  LlmProvider get provider;
  // enum providerEnum {  openai,  gemini,  openrouter,  eurouter,  scaleway,  ovhcloud,  nebius,  neuralwatt,  opencode-go,  opencode,  ollama,  };

  /// Requested `reasoning_effort` for the assistant model (2026-11-20 investigation). `auto` = no explicit level. Only a pair that DECLARES the parameter may name a level — the aggregate answers `422` otherwise, while the mistake is still cheap.
  @BuiltValueField(wireName: r'reasoning_effort')
  ReasoningEffortChoice? get reasoningEffort;
  // enum reasoningEffortEnum {  auto,  minimal,  low,  medium,  high,  };

  @BuiltValueField(wireName: r'vault_key_id')
  String get vaultKeyId;

  @BuiltValueField(wireName: r'vision_model')
  String? get visionModel;

  /// Optional Vision slot (issue #1013): the provider/model/credential that carries PAGE IMAGES (page-streaming schedules and the VLM structural zoning pass). Unset = \"use the assistant pair\", i.e. exactly the behaviour of a configuration written before the slot existed.  `vision_vault_key_id` MAY equal `vault_key_id` when `vision_provider == provider` (same-key reuse) or reference a distinct active credential of the vision provider owned by the caller.
  @BuiltValueField(wireName: r'vision_provider')
  LlmProvider? get visionProvider;
  // enum visionProviderEnum {  openai,  gemini,  openrouter,  eurouter,  scaleway,  ovhcloud,  nebius,  neuralwatt,  opencode-go,  opencode,  ollama,  };

  @BuiltValueField(wireName: r'vision_vault_key_id')
  String? get visionVaultKeyId;

  /// Operator attestation that the VISION provider ACCOUNT has zero data retention enabled (issue #968 semantics, vision-scoped). Separate from `zdr_attested` because it describes a different account as soon as the vision provider differs from the extraction provider. A vision provider that cannot carry page images is refused at save time (`422` `ai-config.vision-provider-unsupported`), never on the first paid page.
  @BuiltValueField(wireName: r'vision_zdr_attested')
  bool? get visionZdrAttested;

  /// Operator attestation that this provider ACCOUNT has zero data retention enabled (issue #968, ADR-041 `D2`). Required to let a provider whose ZDR guarantee is an account switch (Nebius) carry page images; every other provider is unaffected by the flag. Defaults to `false` — an unattested account keeps the vision egress gate fail-closed.
  @BuiltValueField(wireName: r'zdr_attested')
  bool? get zdrAttested;

  CreateAiConfigRequest._();

  factory CreateAiConfigRequest(
      [void updates(CreateAiConfigRequestBuilder b)]) = _$CreateAiConfigRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(CreateAiConfigRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<CreateAiConfigRequest> get serializer =>
      _$CreateAiConfigRequestSerializer();
}

class _$CreateAiConfigRequestSerializer
    implements PrimitiveSerializer<CreateAiConfigRequest> {
  @override
  final Iterable<Type> types = const [
    CreateAiConfigRequest,
    _$CreateAiConfigRequest
  ];

  @override
  final String wireName = r'CreateAiConfigRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    CreateAiConfigRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'assistant_model';
    yield serializers.serialize(
      object.assistantModel,
      specifiedType: const FullType(String),
    );
    if (object.costDisplayPreference != null) {
      yield r'cost_display_preference';
      yield serializers.serialize(
        object.costDisplayPreference,
        specifiedType: const FullType(CostDisplayPreference),
      );
    }
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
    if (object.decisionVaultKeyId != null) {
      yield r'decision_vault_key_id';
      yield serializers.serialize(
        object.decisionVaultKeyId,
        specifiedType: const FullType.nullable(String),
      );
    }
    if (object.imageModel != null) {
      yield r'image_model';
      yield serializers.serialize(
        object.imageModel,
        specifiedType: const FullType.nullable(String),
      );
    }
    yield r'prompts';
    yield serializers.serialize(
      object.prompts,
      specifiedType:
          const FullType(BuiltMap, [FullType(String), FullType(String)]),
    );
    yield r'provider';
    yield serializers.serialize(
      object.provider,
      specifiedType: const FullType(LlmProvider),
    );
    if (object.reasoningEffort != null) {
      yield r'reasoning_effort';
      yield serializers.serialize(
        object.reasoningEffort,
        specifiedType: const FullType(ReasoningEffortChoice),
      );
    }
    yield r'vault_key_id';
    yield serializers.serialize(
      object.vaultKeyId,
      specifiedType: const FullType(String),
    );
    if (object.visionModel != null) {
      yield r'vision_model';
      yield serializers.serialize(
        object.visionModel,
        specifiedType: const FullType.nullable(String),
      );
    }
    if (object.visionProvider != null) {
      yield r'vision_provider';
      yield serializers.serialize(
        object.visionProvider,
        specifiedType: const FullType.nullable(LlmProvider),
      );
    }
    if (object.visionVaultKeyId != null) {
      yield r'vision_vault_key_id';
      yield serializers.serialize(
        object.visionVaultKeyId,
        specifiedType: const FullType.nullable(String),
      );
    }
    if (object.visionZdrAttested != null) {
      yield r'vision_zdr_attested';
      yield serializers.serialize(
        object.visionZdrAttested,
        specifiedType: const FullType(bool),
      );
    }
    if (object.zdrAttested != null) {
      yield r'zdr_attested';
      yield serializers.serialize(
        object.zdrAttested,
        specifiedType: const FullType(bool),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    CreateAiConfigRequest object, {
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
    required CreateAiConfigRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'assistant_model':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.assistantModel = valueDes;
          break;
        case r'cost_display_preference':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(CostDisplayPreference),
          ) as CostDisplayPreference?;
          if (valueDes == null) continue;
          result.costDisplayPreference = valueDes;
          break;
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
        case r'decision_vault_key_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.decisionVaultKeyId = valueDes;
          break;
        case r'image_model':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.imageModel = valueDes;
          break;
        case r'prompts':
          final valueDes = serializers.deserialize(
            value,
            specifiedType:
                const FullType(BuiltMap, [FullType(String), FullType(String)]),
          ) as BuiltMap<String, String>;
          result.prompts.replace(valueDes);
          break;
        case r'provider':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(LlmProvider),
          ) as LlmProvider;
          result.provider = valueDes;
          break;
        case r'reasoning_effort':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(ReasoningEffortChoice),
          ) as ReasoningEffortChoice?;
          if (valueDes == null) continue;
          result.reasoningEffort = valueDes;
          break;
        case r'vault_key_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.vaultKeyId = valueDes;
          break;
        case r'vision_model':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.visionModel = valueDes;
          break;
        case r'vision_provider':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(LlmProvider),
          ) as LlmProvider?;
          if (valueDes == null) continue;
          result.visionProvider = valueDes;
          break;
        case r'vision_vault_key_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.visionVaultKeyId = valueDes;
          break;
        case r'vision_zdr_attested':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(bool),
          ) as bool?;
          if (valueDes == null) continue;
          result.visionZdrAttested = valueDes;
          break;
        case r'zdr_attested':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(bool),
          ) as bool?;
          if (valueDes == null) continue;
          result.zdrAttested = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  CreateAiConfigRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = CreateAiConfigRequestBuilder();
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
