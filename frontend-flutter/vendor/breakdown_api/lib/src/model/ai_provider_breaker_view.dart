// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:breakdown_api/src/model/llm_provider.dart';
import 'package:breakdown_api/src/model/provider_breaker_state.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'ai_provider_breaker_view.g.dart';

/// One `(provider, model)` breaker row (issue #942 W4).  Deliberately **not** the raw `ProviderBreakerSnapshot`: that struct carries `trial_job`, the id of the job currently allowed to run the half-open trial. Serializing it would publish another user's job id, so the wire keeps a boolean instead — the client only needs to know that a trial is in flight.
///
/// Properties:
/// * [consecutiveFailures] - Consecutive retryable failures on this pair, across all users and jobs.
/// * [flapCount] - How often the pair has reopened; a high count is a flapping provider.
/// * [model] - The model half of the breaker key.
/// * [provider]
/// * [retryAt] - The next scheduled probe (`null` while `closed`).
/// * [state] - `closed` admits paid calls; `open`/`half_open` hold them.
/// * [trialGranted] - Whether one un-retried trial call is currently granted for this pair. A boolean, never the trial's job id (see the type doc).
@BuiltValue()
abstract class AiProviderBreakerView
    implements Built<AiProviderBreakerView, AiProviderBreakerViewBuilder> {
  /// Consecutive retryable failures on this pair, across all users and jobs.
  @BuiltValueField(wireName: r'consecutive_failures')
  int get consecutiveFailures;

  /// How often the pair has reopened; a high count is a flapping provider.
  @BuiltValueField(wireName: r'flap_count')
  int get flapCount;

  /// The model half of the breaker key.
  @BuiltValueField(wireName: r'model')
  String get model;

  @BuiltValueField(wireName: r'provider')
  LlmProvider get provider;
  // enum providerEnum {  openai,  gemini,  openrouter,  eurouter,  neuralwatt,  opencode-go,  opencode,  ollama,  };

  /// The next scheduled probe (`null` while `closed`).
  @BuiltValueField(wireName: r'retry_at')
  DateTime? get retryAt;

  /// `closed` admits paid calls; `open`/`half_open` hold them.
  @BuiltValueField(wireName: r'state')
  ProviderBreakerState get state;
  // enum stateEnum {  closed,  open,  half_open,  expired,  };

  /// Whether one un-retried trial call is currently granted for this pair. A boolean, never the trial's job id (see the type doc).
  @BuiltValueField(wireName: r'trial_granted')
  bool get trialGranted;

  AiProviderBreakerView._();

  factory AiProviderBreakerView(
      [void updates(AiProviderBreakerViewBuilder b)]) = _$AiProviderBreakerView;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(AiProviderBreakerViewBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<AiProviderBreakerView> get serializer =>
      _$AiProviderBreakerViewSerializer();
}

class _$AiProviderBreakerViewSerializer
    implements PrimitiveSerializer<AiProviderBreakerView> {
  @override
  final Iterable<Type> types = const [
    AiProviderBreakerView,
    _$AiProviderBreakerView
  ];

  @override
  final String wireName = r'AiProviderBreakerView';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    AiProviderBreakerView object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'consecutive_failures';
    yield serializers.serialize(
      object.consecutiveFailures,
      specifiedType: const FullType(int),
    );
    yield r'flap_count';
    yield serializers.serialize(
      object.flapCount,
      specifiedType: const FullType(int),
    );
    yield r'model';
    yield serializers.serialize(
      object.model,
      specifiedType: const FullType(String),
    );
    yield r'provider';
    yield serializers.serialize(
      object.provider,
      specifiedType: const FullType(LlmProvider),
    );
    if (object.retryAt != null) {
      yield r'retry_at';
      yield serializers.serialize(
        object.retryAt,
        specifiedType: const FullType.nullable(DateTime),
      );
    }
    yield r'state';
    yield serializers.serialize(
      object.state,
      specifiedType: const FullType(ProviderBreakerState),
    );
    yield r'trial_granted';
    yield serializers.serialize(
      object.trialGranted,
      specifiedType: const FullType(bool),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    AiProviderBreakerView object, {
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
    required AiProviderBreakerViewBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'consecutive_failures':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.consecutiveFailures = valueDes;
          break;
        case r'flap_count':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.flapCount = valueDes;
          break;
        case r'model':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.model = valueDes;
          break;
        case r'provider':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(LlmProvider),
          ) as LlmProvider;
          result.provider = valueDes;
          break;
        case r'retry_at':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(DateTime),
          ) as DateTime?;
          if (valueDes == null) continue;
          result.retryAt = valueDes;
          break;
        case r'state':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(ProviderBreakerState),
          ) as ProviderBreakerState;
          result.state = valueDes;
          break;
        case r'trial_granted':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.trialGranted = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  AiProviderBreakerView deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = AiProviderBreakerViewBuilder();
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
