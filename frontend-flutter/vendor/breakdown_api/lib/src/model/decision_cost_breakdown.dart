// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:breakdown_api/src/model/llm_provider.dart';
import 'package:breakdown_api/src/model/pricing_source.dart';
import 'package:breakdown_api/src/model/currency.dart';
import 'package:breakdown_api/src/model/cost_status.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'decision_cost_breakdown.g.dart';

/// The **Decision-Model** component of a job's cost snapshot (issue #768).  A job's Decision Model may be a different provider/model than its extraction model (split billing, #722/#723). Its usage is accumulated separately and priced from **its own** `ai_model_pricing` row — never folded into the extraction component and never costed at the extraction rates.  The usage counts are recorded whether or not the component could be priced, so an unpriced Decision Model still states how much it consumed. The priced fields stay `None` when [`Self::status`] is [`CostStatus::Unknown`] — the honest-unknown rule of #675, applied per component: no fabricated rate, no substituted extraction rate, no `0`.
///
/// Properties:
/// * [cachedInputRateNanoPerMillion]
/// * [cachedTokensIn]
/// * [currency] - Currency of the component's own rate card (design D2: no conversion).
/// * [energyCostNano] - Priced effective energy cost of this component (`min(raw, token)` when the provider caps energy by token cost), `None` when unpriced.
/// * [energyMillijoules]
/// * [energyRateNanoPerKwh]
/// * [inputRateNanoPerMillion]
/// * [model]
/// * [outputRateNanoPerMillion]
/// * [priceAsOf]
/// * [pricingSource]
/// * [provider]
/// * [status] - `Known` when the component's `(provider, model)` had a pricing row at completion; `Unknown` otherwise. `NotApplicable` never occurs: the component exists only for a job that issued a Decision-Model call.
/// * [tokenCostNano] - Priced token cost of this component, `None` when unpriced.
/// * [tokensIn]
/// * [tokensOut]
@BuiltValue()
abstract class DecisionCostBreakdown
    implements Built<DecisionCostBreakdown, DecisionCostBreakdownBuilder> {
  @BuiltValueField(wireName: r'cached_input_rate_nano_per_million')
  int? get cachedInputRateNanoPerMillion;

  @BuiltValueField(wireName: r'cached_tokens_in')
  int get cachedTokensIn;

  /// Currency of the component's own rate card (design D2: no conversion).
  @BuiltValueField(wireName: r'currency')
  Currency? get currency;
  // enum currencyEnum {  USD,  EUR,  };

  /// Priced effective energy cost of this component (`min(raw, token)` when the provider caps energy by token cost), `None` when unpriced.
  @BuiltValueField(wireName: r'energy_cost_nano')
  int? get energyCostNano;

  @BuiltValueField(wireName: r'energy_millijoules')
  int get energyMillijoules;

  @BuiltValueField(wireName: r'energy_rate_nano_per_kwh')
  int? get energyRateNanoPerKwh;

  @BuiltValueField(wireName: r'input_rate_nano_per_million')
  int? get inputRateNanoPerMillion;

  @BuiltValueField(wireName: r'model')
  String get model;

  @BuiltValueField(wireName: r'output_rate_nano_per_million')
  int? get outputRateNanoPerMillion;

  @BuiltValueField(wireName: r'price_as_of')
  DateTime? get priceAsOf;

  @BuiltValueField(wireName: r'pricing_source')
  PricingSource? get pricingSource;
  // enum pricingSourceEnum {  curated_seed,  provider_live,  models_dev,  };

  @BuiltValueField(wireName: r'provider')
  LlmProvider get provider;
  // enum providerEnum {  openai,  gemini,  openrouter,  eurouter,  neuralwatt,  opencode-go,  opencode,  ollama,  };

  /// `Known` when the component's `(provider, model)` had a pricing row at completion; `Unknown` otherwise. `NotApplicable` never occurs: the component exists only for a job that issued a Decision-Model call.
  @BuiltValueField(wireName: r'status')
  CostStatus get status;
  // enum statusEnum {  known,  unknown,  not_applicable,  };

  /// Priced token cost of this component, `None` when unpriced.
  @BuiltValueField(wireName: r'token_cost_nano')
  int? get tokenCostNano;

  @BuiltValueField(wireName: r'tokens_in')
  int get tokensIn;

  @BuiltValueField(wireName: r'tokens_out')
  int get tokensOut;

  DecisionCostBreakdown._();

  factory DecisionCostBreakdown(
      [void updates(DecisionCostBreakdownBuilder b)]) = _$DecisionCostBreakdown;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(DecisionCostBreakdownBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<DecisionCostBreakdown> get serializer =>
      _$DecisionCostBreakdownSerializer();
}

class _$DecisionCostBreakdownSerializer
    implements PrimitiveSerializer<DecisionCostBreakdown> {
  @override
  final Iterable<Type> types = const [
    DecisionCostBreakdown,
    _$DecisionCostBreakdown
  ];

  @override
  final String wireName = r'DecisionCostBreakdown';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    DecisionCostBreakdown object, {
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
    if (object.currency != null) {
      yield r'currency';
      yield serializers.serialize(
        object.currency,
        specifiedType: const FullType.nullable(Currency),
      );
    }
    if (object.energyCostNano != null) {
      yield r'energy_cost_nano';
      yield serializers.serialize(
        object.energyCostNano,
        specifiedType: const FullType.nullable(int),
      );
    }
    yield r'energy_millijoules';
    yield serializers.serialize(
      object.energyMillijoules,
      specifiedType: const FullType(int),
    );
    if (object.energyRateNanoPerKwh != null) {
      yield r'energy_rate_nano_per_kwh';
      yield serializers.serialize(
        object.energyRateNanoPerKwh,
        specifiedType: const FullType.nullable(int),
      );
    }
    if (object.inputRateNanoPerMillion != null) {
      yield r'input_rate_nano_per_million';
      yield serializers.serialize(
        object.inputRateNanoPerMillion,
        specifiedType: const FullType.nullable(int),
      );
    }
    yield r'model';
    yield serializers.serialize(
      object.model,
      specifiedType: const FullType(String),
    );
    if (object.outputRateNanoPerMillion != null) {
      yield r'output_rate_nano_per_million';
      yield serializers.serialize(
        object.outputRateNanoPerMillion,
        specifiedType: const FullType.nullable(int),
      );
    }
    if (object.priceAsOf != null) {
      yield r'price_as_of';
      yield serializers.serialize(
        object.priceAsOf,
        specifiedType: const FullType.nullable(DateTime),
      );
    }
    if (object.pricingSource != null) {
      yield r'pricing_source';
      yield serializers.serialize(
        object.pricingSource,
        specifiedType: const FullType.nullable(PricingSource),
      );
    }
    yield r'provider';
    yield serializers.serialize(
      object.provider,
      specifiedType: const FullType(LlmProvider),
    );
    yield r'status';
    yield serializers.serialize(
      object.status,
      specifiedType: const FullType(CostStatus),
    );
    if (object.tokenCostNano != null) {
      yield r'token_cost_nano';
      yield serializers.serialize(
        object.tokenCostNano,
        specifiedType: const FullType.nullable(int),
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
    DecisionCostBreakdown object, {
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
    required DecisionCostBreakdownBuilder result,
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
        case r'currency':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(Currency),
          ) as Currency?;
          if (valueDes == null) continue;
          result.currency = valueDes;
          break;
        case r'energy_cost_nano':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(int),
          ) as int?;
          if (valueDes == null) continue;
          result.energyCostNano = valueDes;
          break;
        case r'energy_millijoules':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.energyMillijoules = valueDes;
          break;
        case r'energy_rate_nano_per_kwh':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(int),
          ) as int?;
          if (valueDes == null) continue;
          result.energyRateNanoPerKwh = valueDes;
          break;
        case r'input_rate_nano_per_million':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(int),
          ) as int?;
          if (valueDes == null) continue;
          result.inputRateNanoPerMillion = valueDes;
          break;
        case r'model':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.model = valueDes;
          break;
        case r'output_rate_nano_per_million':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(int),
          ) as int?;
          if (valueDes == null) continue;
          result.outputRateNanoPerMillion = valueDes;
          break;
        case r'price_as_of':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(DateTime),
          ) as DateTime?;
          if (valueDes == null) continue;
          result.priceAsOf = valueDes;
          break;
        case r'pricing_source':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(PricingSource),
          ) as PricingSource?;
          if (valueDes == null) continue;
          result.pricingSource = valueDes;
          break;
        case r'provider':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(LlmProvider),
          ) as LlmProvider;
          result.provider = valueDes;
          break;
        case r'status':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(CostStatus),
          ) as CostStatus;
          result.status = valueDes;
          break;
        case r'token_cost_nano':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(int),
          ) as int?;
          if (valueDes == null) continue;
          result.tokenCostNano = valueDes;
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
  DecisionCostBreakdown deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = DecisionCostBreakdownBuilder();
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
