// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:breakdown_api/src/model/ai_provider_breaker_view.dart';
import 'package:breakdown_api/src/model/llm_provider.dart';
import 'package:breakdown_api/src/model/account_probe_status.dart';
import 'package:built_collection/built_collection.dart';
import 'package:breakdown_api/src/model/ai_provider_budget_view.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'ai_provider_health_view.g.dart';

/// The provider-health read (issue #942 W4).
///
/// Properties:
/// * [breakers] - The `(provider, model)` breaker rows, ordered by model for a stable rendering.
/// * [budget] - The remaining budget, or `null` when the provider reports none / there is no credential to read it with.
/// * [credentialConfigured] - Whether the caller has an active Vault binding for this provider.  `false` is a complete answer: `probe_status` is then `unknown` and `budget` is `null` — the route never fabricates a verdict it did not measure, and never answers `404` for a user who simply has not saved a key yet.
/// * [probeStatus] - The account-usability verdict of the zero-token read.
/// * [provider] - The provider this answer is about, echoed as the canonical wire key.
@BuiltValue()
abstract class AiProviderHealthView
    implements Built<AiProviderHealthView, AiProviderHealthViewBuilder> {
  /// The `(provider, model)` breaker rows, ordered by model for a stable rendering.
  @BuiltValueField(wireName: r'breakers')
  BuiltList<AiProviderBreakerView> get breakers;

  /// The remaining budget, or `null` when the provider reports none / there is no credential to read it with.
  @BuiltValueField(wireName: r'budget')
  AiProviderBudgetView? get budget;

  /// Whether the caller has an active Vault binding for this provider.  `false` is a complete answer: `probe_status` is then `unknown` and `budget` is `null` — the route never fabricates a verdict it did not measure, and never answers `404` for a user who simply has not saved a key yet.
  @BuiltValueField(wireName: r'credential_configured')
  bool get credentialConfigured;

  /// The account-usability verdict of the zero-token read.
  @BuiltValueField(wireName: r'probe_status')
  AccountProbeStatus get probeStatus;
  // enum probeStatusEnum {  usable,  not_usable,  unknown,  };

  /// The provider this answer is about, echoed as the canonical wire key.
  @BuiltValueField(wireName: r'provider')
  LlmProvider get provider;
  // enum providerEnum {  openai,  gemini,  openrouter,  eurouter,  neuralwatt,  opencode-go,  opencode,  ollama,  };

  AiProviderHealthView._();

  factory AiProviderHealthView([void updates(AiProviderHealthViewBuilder b)]) =
      _$AiProviderHealthView;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(AiProviderHealthViewBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<AiProviderHealthView> get serializer =>
      _$AiProviderHealthViewSerializer();
}

class _$AiProviderHealthViewSerializer
    implements PrimitiveSerializer<AiProviderHealthView> {
  @override
  final Iterable<Type> types = const [
    AiProviderHealthView,
    _$AiProviderHealthView
  ];

  @override
  final String wireName = r'AiProviderHealthView';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    AiProviderHealthView object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'breakers';
    yield serializers.serialize(
      object.breakers,
      specifiedType:
          const FullType(BuiltList, [FullType(AiProviderBreakerView)]),
    );
    if (object.budget != null) {
      yield r'budget';
      yield serializers.serialize(
        object.budget,
        specifiedType: const FullType.nullable(AiProviderBudgetView),
      );
    }
    yield r'credential_configured';
    yield serializers.serialize(
      object.credentialConfigured,
      specifiedType: const FullType(bool),
    );
    yield r'probe_status';
    yield serializers.serialize(
      object.probeStatus,
      specifiedType: const FullType(AccountProbeStatus),
    );
    yield r'provider';
    yield serializers.serialize(
      object.provider,
      specifiedType: const FullType(LlmProvider),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    AiProviderHealthView object, {
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
    required AiProviderHealthViewBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'breakers':
          final valueDes = serializers.deserialize(
            value,
            specifiedType:
                const FullType(BuiltList, [FullType(AiProviderBreakerView)]),
          ) as BuiltList<AiProviderBreakerView>;
          result.breakers.replace(valueDes);
          break;
        case r'budget':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(AiProviderBudgetView),
          ) as AiProviderBudgetView?;
          if (valueDes == null) continue;
          result.budget.replace(valueDes);
          break;
        case r'credential_configured':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.credentialConfigured = valueDes;
          break;
        case r'probe_status':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(AccountProbeStatus),
          ) as AccountProbeStatus;
          result.probeStatus = valueDes;
          break;
        case r'provider':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(LlmProvider),
          ) as LlmProvider;
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
  AiProviderHealthView deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = AiProviderHealthViewBuilder();
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
