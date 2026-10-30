// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'token_cost_breakdown.g.dart';

/// Token-based cost of the **extraction** component of one import, in nano-units. Rates are the snapshot rates active at completion time.  Since issue #768 the counts are extraction-only: Decision-Model calls are accumulated into their own [`DecisionCostBreakdown`] and priced with the Decision Model's rate card, never folded in here.
///
/// Properties:
/// * [cachedInputRateNanoPerMillion] - Snapshot cache-hit rate; `None` when the catalog had none (cached tokens are then billed at the plain input rate).
/// * [cachedTokensIn]
/// * [inputRateNanoPerMillion]
/// * [outputRateNanoPerMillion]
/// * [tokensIn]
/// * [tokensOut]
/// * [totalNano] - `uncached_input + cached_input + output` cost, half-up rounded to nano-units, as one total.
@BuiltValue()
abstract class TokenCostBreakdown
    implements Built<TokenCostBreakdown, TokenCostBreakdownBuilder> {
  /// Snapshot cache-hit rate; `None` when the catalog had none (cached tokens are then billed at the plain input rate).
  @BuiltValueField(wireName: r'cached_input_rate_nano_per_million')
  int? get cachedInputRateNanoPerMillion;

  @BuiltValueField(wireName: r'cached_tokens_in')
  int get cachedTokensIn;

  @BuiltValueField(wireName: r'input_rate_nano_per_million')
  int get inputRateNanoPerMillion;

  @BuiltValueField(wireName: r'output_rate_nano_per_million')
  int get outputRateNanoPerMillion;

  @BuiltValueField(wireName: r'tokens_in')
  int get tokensIn;

  @BuiltValueField(wireName: r'tokens_out')
  int get tokensOut;

  /// `uncached_input + cached_input + output` cost, half-up rounded to nano-units, as one total.
  @BuiltValueField(wireName: r'total_nano')
  int get totalNano;

  TokenCostBreakdown._();

  factory TokenCostBreakdown([void updates(TokenCostBreakdownBuilder b)]) =
      _$TokenCostBreakdown;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(TokenCostBreakdownBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<TokenCostBreakdown> get serializer =>
      _$TokenCostBreakdownSerializer();
}

class _$TokenCostBreakdownSerializer
    implements PrimitiveSerializer<TokenCostBreakdown> {
  @override
  final Iterable<Type> types = const [TokenCostBreakdown, _$TokenCostBreakdown];

  @override
  final String wireName = r'TokenCostBreakdown';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    TokenCostBreakdown object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.cachedInputRateNanoPerMillion != null) {
      yield r'cached_input_rate_nano_per_million';
      yield serializers.serialize(
        object.cachedInputRateNanoPerMillion,
        specifiedType: const FullType.nullable(int),
      );
    }
    yield r'cached_tokens_in';
    yield serializers.serialize(
      object.cachedTokensIn,
      specifiedType: const FullType(int),
    );
    yield r'input_rate_nano_per_million';
    yield serializers.serialize(
      object.inputRateNanoPerMillion,
      specifiedType: const FullType(int),
    );
    yield r'output_rate_nano_per_million';
    yield serializers.serialize(
      object.outputRateNanoPerMillion,
      specifiedType: const FullType(int),
    );
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
    yield r'total_nano';
    yield serializers.serialize(
      object.totalNano,
      specifiedType: const FullType(int),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    TokenCostBreakdown object, {
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
    required TokenCostBreakdownBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'cached_input_rate_nano_per_million':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(int),
          ) as int?;
          if (valueDes == null) continue;
          result.cachedInputRateNanoPerMillion = valueDes;
          break;
        case r'cached_tokens_in':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.cachedTokensIn = valueDes;
          break;
        case r'input_rate_nano_per_million':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.inputRateNanoPerMillion = valueDes;
          break;
        case r'output_rate_nano_per_million':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.outputRateNanoPerMillion = valueDes;
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
        case r'total_nano':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.totalNano = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  TokenCostBreakdown deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = TokenCostBreakdownBuilder();
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
