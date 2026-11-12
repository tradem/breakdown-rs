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

part 'update_ai_config_request.g.dart';

/// UpdateAiConfigRequest
///
/// Properties:
/// * [assistantModel]
/// * [costDisplayPreference] - See [`CreateAiConfigRequest`] (issue #675). `None` (omitted) keeps the stored preference — an omitted field must not reset an existing `energy` preference back to `token`.
/// * [decisionModel]
/// * [decisionProvider] - Decision Model slot (issue #722), tri-state: an omitted field keeps the stored configuration, `null` clears it, a value replaces it. `deserialize_optional_nullable` is what makes the outer `Some` an EXPLICIT signal — plain `#[serde(default)]` would fold `null` and \"absent\" together and the clear path would be unreachable.
/// * [decisionVaultKeyId]
/// * [imageModel]
/// * [prompts]
/// * [provider]
/// * [vaultKeyId]
/// * [version] - Aggregate version for optimistic locking.  The canonical version contract is **1-based**: `AggregateVersion::INITIAL = 1`, and every mutation increments the version by one.  The SierraDB stream version (0-based) is an infrastructure-internal detail. The translation rule is: `domain_version = stream_version + 1` (and inversely `stream_version = domain_version - 1`) which is performed exclusively inside `crates::infra` at the `*Commands` adapter boundary. `core` does not reference `stream_version`, `ExpectedVersion`, or `CurrentVersion`.
@BuiltValue()
abstract class UpdateAiConfigRequest
    implements Built<UpdateAiConfigRequest, UpdateAiConfigRequestBuilder> {
  @BuiltValueField(wireName: r'assistant_model')
  String get assistantModel;

  /// See [`CreateAiConfigRequest`] (issue #675). `None` (omitted) keeps the stored preference — an omitted field must not reset an existing `energy` preference back to `token`.
  @BuiltValueField(wireName: r'cost_display_preference')
  CostDisplayPreference? get costDisplayPreference;
  // enum costDisplayPreferenceEnum {  token,  energy,  };

  @BuiltValueField(wireName: r'decision_model')
  String? get decisionModel;

  /// Decision Model slot (issue #722), tri-state: an omitted field keeps the stored configuration, `null` clears it, a value replaces it. `deserialize_optional_nullable` is what makes the outer `Some` an EXPLICIT signal — plain `#[serde(default)]` would fold `null` and \"absent\" together and the clear path would be unreachable.
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

  /// Aggregate version for optimistic locking.  The canonical version contract is **1-based**: `AggregateVersion::INITIAL = 1`, and every mutation increments the version by one.  The SierraDB stream version (0-based) is an infrastructure-internal detail. The translation rule is: `domain_version = stream_version + 1` (and inversely `stream_version = domain_version - 1`) which is performed exclusively inside `crates::infra` at the `*Commands` adapter boundary. `core` does not reference `stream_version`, `ExpectedVersion`, or `CurrentVersion`.
  @BuiltValueField(wireName: r'version')
  int get version;

  UpdateAiConfigRequest._();

  factory UpdateAiConfigRequest(
      [void updates(UpdateAiConfigRequestBuilder b)]) = _$UpdateAiConfigRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(UpdateAiConfigRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<UpdateAiConfigRequest> get serializer =>
      _$UpdateAiConfigRequestSerializer();
}

class _$UpdateAiConfigRequestSerializer
    implements PrimitiveSerializer<UpdateAiConfigRequest> {
  @override
  final Iterable<Type> types = const [
    UpdateAiConfigRequest,
    _$UpdateAiConfigRequest
  ];

  @override
  final String wireName = r'UpdateAiConfigRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    UpdateAiConfigRequest object, {
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
        specifiedType: const FullType.nullable(CostDisplayPreference),
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
    yield r'version';
    yield serializers.serialize(
      object.version,
      specifiedType: const FullType(int),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    UpdateAiConfigRequest object, {
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
    required UpdateAiConfigRequestBuilder result,
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
        case r'version':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.version = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  UpdateAiConfigRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = UpdateAiConfigRequestBuilder();
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
