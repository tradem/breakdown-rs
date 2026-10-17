// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:breakdown_api/src/model/pricing_source.dart';
import 'package:breakdown_api/src/model/currency.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'model_pricing.g.dart';

/// One model's pricing snapshot in integer nano-currency units ($10^{-9}$ of the currency unit: `1_000_000_000 = 1.00 USD/EUR`). Rates are per 1,000,000 tokens. Optional slots stay `None` when the provider does not offer the dimension — never a fabricated zero (issue #675).
///
/// Properties:
/// * [cachedInputNanoPerMillion] - Rate for cache-hit prompt tokens, when the provider reports one. Absent means cached tokens are billed at the plain input rate.
/// * [currency]
/// * [energyCappedByToken] - Neuralwatt surge-protection cap: the energy cost never exceeds the token cost of the same call.
/// * [energyNanoPerKwh] - Energy billing rate (e.g. Neuralwatt at `$10.00 / kWh` = `10_000_000_000` nano-USD per kWh), when the provider offers it.
/// * [imageNanoPerUnit] - Alternative flat per-image rate. #673 slot; never combined with `image_output_nano_per_million` by a cost computation.
/// * [imageOutputNanoPerMillion] - Rate per 1,000,000 image-output tokens (e.g. Gemini *Nano Banana*: one 1024×1024 image consumes 1,290 image-output tokens). #673 slot.
/// * [inputNanoPerMillion]
/// * [outputNanoPerMillion]
/// * [priceAsOf] - When this price was captured. A completed job's persisted cost snapshot never changes when newer prices arrive.
/// * [pricingSource]
@BuiltValue()
abstract class ModelPricing
    implements Built<ModelPricing, ModelPricingBuilder> {
  /// Rate for cache-hit prompt tokens, when the provider reports one. Absent means cached tokens are billed at the plain input rate.
  @BuiltValueField(wireName: r'cached_input_nano_per_million')
  int? get cachedInputNanoPerMillion;

  @BuiltValueField(wireName: r'currency')
  Currency get currency;
  // enum currencyEnum {  USD,  EUR,  };

  /// Neuralwatt surge-protection cap: the energy cost never exceeds the token cost of the same call.
  @BuiltValueField(wireName: r'energy_capped_by_token')
  bool? get energyCappedByToken;

  /// Energy billing rate (e.g. Neuralwatt at `$10.00 / kWh` = `10_000_000_000` nano-USD per kWh), when the provider offers it.
  @BuiltValueField(wireName: r'energy_nano_per_kwh')
  int? get energyNanoPerKwh;

  /// Alternative flat per-image rate. #673 slot; never combined with `image_output_nano_per_million` by a cost computation.
  @BuiltValueField(wireName: r'image_nano_per_unit')
  int? get imageNanoPerUnit;

  /// Rate per 1,000,000 image-output tokens (e.g. Gemini *Nano Banana*: one 1024×1024 image consumes 1,290 image-output tokens). #673 slot.
  @BuiltValueField(wireName: r'image_output_nano_per_million')
  int? get imageOutputNanoPerMillion;

  @BuiltValueField(wireName: r'input_nano_per_million')
  int get inputNanoPerMillion;

  @BuiltValueField(wireName: r'output_nano_per_million')
  int get outputNanoPerMillion;

  /// When this price was captured. A completed job's persisted cost snapshot never changes when newer prices arrive.
  @BuiltValueField(wireName: r'price_as_of')
  DateTime get priceAsOf;

  @BuiltValueField(wireName: r'pricing_source')
  PricingSource get pricingSource;
  // enum pricingSourceEnum {  curated_seed,  provider_live,  models_dev,  };

  ModelPricing._();

  factory ModelPricing([void updates(ModelPricingBuilder b)]) = _$ModelPricing;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ModelPricingBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ModelPricing> get serializer => _$ModelPricingSerializer();
}

class _$ModelPricingSerializer implements PrimitiveSerializer<ModelPricing> {
  @override
  final Iterable<Type> types = const [ModelPricing, _$ModelPricing];

  @override
  final String wireName = r'ModelPricing';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ModelPricing object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.cachedInputNanoPerMillion != null) {
      yield r'cached_input_nano_per_million';
      yield serializers.serialize(
        object.cachedInputNanoPerMillion,
        specifiedType: const FullType.nullable(int),
      );
    }
    yield r'currency';
    yield serializers.serialize(
      object.currency,
      specifiedType: const FullType(Currency),
    );
    if (object.energyCappedByToken != null) {
      yield r'energy_capped_by_token';
      yield serializers.serialize(
        object.energyCappedByToken,
        specifiedType: const FullType(bool),
      );
    }
    if (object.energyNanoPerKwh != null) {
      yield r'energy_nano_per_kwh';
      yield serializers.serialize(
        object.energyNanoPerKwh,
        specifiedType: const FullType.nullable(int),
      );
    }
    if (object.imageNanoPerUnit != null) {
      yield r'image_nano_per_unit';
      yield serializers.serialize(
        object.imageNanoPerUnit,
        specifiedType: const FullType.nullable(int),
      );
    }
    if (object.imageOutputNanoPerMillion != null) {
      yield r'image_output_nano_per_million';
      yield serializers.serialize(
        object.imageOutputNanoPerMillion,
        specifiedType: const FullType.nullable(int),
      );
    }
    yield r'input_nano_per_million';
    yield serializers.serialize(
      object.inputNanoPerMillion,
      specifiedType: const FullType(int),
    );
    yield r'output_nano_per_million';
    yield serializers.serialize(
      object.outputNanoPerMillion,
      specifiedType: const FullType(int),
    );
    yield r'price_as_of';
    yield serializers.serialize(
      object.priceAsOf,
      specifiedType: const FullType(DateTime),
    );
    yield r'pricing_source';
    yield serializers.serialize(
      object.pricingSource,
      specifiedType: const FullType(PricingSource),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    ModelPricing object, {
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
    required ModelPricingBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'cached_input_nano_per_million':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(int),
          ) as int?;
          if (valueDes == null) continue;
          result.cachedInputNanoPerMillion = valueDes;
          break;
        case r'currency':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(Currency),
          ) as Currency;
          result.currency = valueDes;
          break;
        case r'energy_capped_by_token':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(bool),
          ) as bool?;
          if (valueDes == null) continue;
          result.energyCappedByToken = valueDes;
          break;
        case r'energy_nano_per_kwh':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(int),
          ) as int?;
          if (valueDes == null) continue;
          result.energyNanoPerKwh = valueDes;
          break;
        case r'image_nano_per_unit':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(int),
          ) as int?;
          if (valueDes == null) continue;
          result.imageNanoPerUnit = valueDes;
          break;
        case r'image_output_nano_per_million':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(int),
          ) as int?;
          if (valueDes == null) continue;
          result.imageOutputNanoPerMillion = valueDes;
          break;
        case r'input_nano_per_million':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.inputNanoPerMillion = valueDes;
          break;
        case r'output_nano_per_million':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.outputNanoPerMillion = valueDes;
          break;
        case r'price_as_of':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.priceAsOf = valueDes;
          break;
        case r'pricing_source':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(PricingSource),
          ) as PricingSource;
          result.pricingSource = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  ModelPricing deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ModelPricingBuilder();
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
