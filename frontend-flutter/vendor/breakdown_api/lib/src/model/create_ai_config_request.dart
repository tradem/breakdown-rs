// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:breakdown_api/src/model/llm_provider.dart';
import 'package:built_collection/built_collection.dart';
import 'package:breakdown_api/src/model/cost_display_preference.dart';
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
/// * [vaultKeyId]
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
  // enum decisionProviderEnum {  openai,  gemini,  openrouter,  eurouter,  neuralwatt,  opencode-go,  opencode,  ollama,  };

  @BuiltValueField(wireName: r'decision_vault_key_id')
  String? get decisionVaultKeyId;

  @BuiltValueField(wireName: r'image_model')
  String? get imageModel;

  @BuiltValueField(wireName: r'prompts')
  BuiltMap<String, String> get prompts;

  @BuiltValueField(wireName: r'provider')
  LlmProvider get provider;
  // enum providerEnum {  openai,  gemini,  openrouter,  eurouter,  neuralwatt,  opencode-go,  opencode,  ollama,  };

  @BuiltValueField(wireName: r'vault_key_id')
  String get vaultKeyId;

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
    yield r'vault_key_id';
    yield serializers.serialize(
      object.vaultKeyId,
      specifiedType: const FullType(String),
    );
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
        case r'vault_key_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.vaultKeyId = valueDes;
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
