// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:breakdown_api/src/model/llm_provider.dart';
import 'package:breakdown_api/src/model/provider_breaker_state.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'provider_hold.g.dart';

/// Why a job is **waiting** on its provider, and until when (issue #871).  A held job stays [`JobStatus::Failed`] on purpose: adding a `waiting_for_provider` status would have to be classified correctly in `is_terminal()`, `is_non_resumable()`, the payload retention, `dev_reset` and the claim predicates — plus a new ARB key, glyph and golden in the client — to say what this additive field says for free. `#822`'s banner already renders \"provider degraded · next attempt at X\"; this is the honest extension of that copy.  The field is cleared by **every** other lifecycle write (claim, `mark_succeeded`, `mark_failed`, `mark_payload_unavailable`, ordinary dead-letter) — with exactly one exception: the hold-expiry write keeps it with `state = Expired`, because that marker is the only durable signal separating an expiry from a spent retry budget.
///
/// Properties:
/// * [chunksDone] - Chunks already paid for and stored — the resume point (D-B2). `0` in a build without the chunk store, which is honest: nothing was stored.
/// * [holdDeadline] - Absolute deadline of the whole hold **series** (D-C4): the job dead-letters at this instant without spending a retry. Lives on the job row (`provider_hold_series_started_at`) rather than in this struct, so a short recovery cannot restart the budget.
/// * [model] - The model the job was resolved against. Together with `provider` this is the breaker key (D-A1).
/// * [provider] - The provider whose endpoint is degraded.
/// * [reasonCode] - The registered problem code that opened the hold — today always `ai-import.llm-provider-unavailable` (no new code, D-X1). The client keeps rendering its existing per-code narrative.
/// * [state] - `open`/`half_open` while waiting; `expired` on the terminal expiry write.
/// * [until] - The breaker's next probe time — also this job's `next_attempt_at`.
@BuiltValue()
abstract class ProviderHold
    implements Built<ProviderHold, ProviderHoldBuilder> {
  /// Chunks already paid for and stored — the resume point (D-B2). `0` in a build without the chunk store, which is honest: nothing was stored.
  @BuiltValueField(wireName: r'chunks_done')
  int get chunksDone;

  /// Absolute deadline of the whole hold **series** (D-C4): the job dead-letters at this instant without spending a retry. Lives on the job row (`provider_hold_series_started_at`) rather than in this struct, so a short recovery cannot restart the budget.
  @BuiltValueField(wireName: r'hold_deadline')
  DateTime get holdDeadline;

  /// The model the job was resolved against. Together with `provider` this is the breaker key (D-A1).
  @BuiltValueField(wireName: r'model')
  String get model;

  /// The provider whose endpoint is degraded.
  @BuiltValueField(wireName: r'provider')
  LlmProvider get provider;
  // enum providerEnum {  openai,  gemini,  openrouter,  eurouter,  neuralwatt,  opencode-go,  opencode,  ollama,  };

  /// The registered problem code that opened the hold — today always `ai-import.llm-provider-unavailable` (no new code, D-X1). The client keeps rendering its existing per-code narrative.
  @BuiltValueField(wireName: r'reason_code')
  String get reasonCode;

  /// `open`/`half_open` while waiting; `expired` on the terminal expiry write.
  @BuiltValueField(wireName: r'state')
  ProviderBreakerState get state;
  // enum stateEnum {  closed,  open,  half_open,  expired,  };

  /// The breaker's next probe time — also this job's `next_attempt_at`.
  @BuiltValueField(wireName: r'until')
  DateTime get until;

  ProviderHold._();

  factory ProviderHold([void updates(ProviderHoldBuilder b)]) = _$ProviderHold;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ProviderHoldBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ProviderHold> get serializer => _$ProviderHoldSerializer();
}

class _$ProviderHoldSerializer implements PrimitiveSerializer<ProviderHold> {
  @override
  final Iterable<Type> types = const [ProviderHold, _$ProviderHold];

  @override
  final String wireName = r'ProviderHold';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ProviderHold object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'chunks_done';
    yield serializers.serialize(
      object.chunksDone,
      specifiedType: const FullType(int),
    );
    yield r'hold_deadline';
    yield serializers.serialize(
      object.holdDeadline,
      specifiedType: const FullType(DateTime),
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
    yield r'reason_code';
    yield serializers.serialize(
      object.reasonCode,
      specifiedType: const FullType(String),
    );
    yield r'state';
    yield serializers.serialize(
      object.state,
      specifiedType: const FullType(ProviderBreakerState),
    );
    yield r'until';
    yield serializers.serialize(
      object.until,
      specifiedType: const FullType(DateTime),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    ProviderHold object, {
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
    required ProviderHoldBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'chunks_done':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.chunksDone = valueDes;
          break;
        case r'hold_deadline':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.holdDeadline = valueDes;
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
        case r'reason_code':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.reasonCode = valueDes;
          break;
        case r'state':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(ProviderBreakerState),
          ) as ProviderBreakerState;
          result.state = valueDes;
          break;
        case r'until':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.until = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  ProviderHold deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ProviderHoldBuilder();
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
