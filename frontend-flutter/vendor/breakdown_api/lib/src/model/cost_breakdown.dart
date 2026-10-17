// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:breakdown_api/src/model/pricing_source.dart';
import 'package:breakdown_api/src/model/currency.dart';
import 'package:breakdown_api/src/model/token_cost_breakdown.dart';
import 'package:breakdown_api/src/model/cost_status.dart';
import 'package:breakdown_api/src/model/image_cost_breakdown.dart';
import 'package:breakdown_api/src/model/energy_cost_breakdown.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'cost_breakdown.g.dart';

/// Immutable per-import cost snapshot persisted on a completed job (design D4). Honesty rule: `Known` populates breakdowns; `Unknown` and `NotApplicable` leave them `None` — never a fabricated zero.
///
/// Properties:
/// * [currency] - Present only for `Known` snapshots.
/// * [energyCost]
/// * [imageCost]
/// * [priceAsOf] - Price snapshot timestamp of the pricing row used for computation.
/// * [pricingSource]
/// * [status]
/// * [tokenCost]
@BuiltValue()
abstract class CostBreakdown
    implements Built<CostBreakdown, CostBreakdownBuilder> {
  /// Present only for `Known` snapshots.
  @BuiltValueField(wireName: r'currency')
  Currency? get currency;
  // enum currencyEnum {  USD,  EUR,  };

  @BuiltValueField(wireName: r'energy_cost')
  EnergyCostBreakdown? get energyCost;

  @BuiltValueField(wireName: r'image_cost')
  ImageCostBreakdown? get imageCost;

  /// Price snapshot timestamp of the pricing row used for computation.
  @BuiltValueField(wireName: r'price_as_of')
  DateTime? get priceAsOf;

  @BuiltValueField(wireName: r'pricing_source')
  PricingSource? get pricingSource;
  // enum pricingSourceEnum {  curated_seed,  provider_live,  models_dev,  };

  @BuiltValueField(wireName: r'status')
  CostStatus get status;
  // enum statusEnum {  known,  unknown,  not_applicable,  };

  @BuiltValueField(wireName: r'token_cost')
  TokenCostBreakdown? get tokenCost;

  CostBreakdown._();

  factory CostBreakdown([void updates(CostBreakdownBuilder b)]) =
      _$CostBreakdown;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(CostBreakdownBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<CostBreakdown> get serializer =>
      _$CostBreakdownSerializer();
}

class _$CostBreakdownSerializer implements PrimitiveSerializer<CostBreakdown> {
  @override
  final Iterable<Type> types = const [CostBreakdown, _$CostBreakdown];

  @override
  final String wireName = r'CostBreakdown';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    CostBreakdown object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.currency != null) {
      yield r'currency';
      yield serializers.serialize(
        object.currency,
        specifiedType: const FullType.nullable(Currency),
      );
    }
    if (object.energyCost != null) {
      yield r'energy_cost';
      yield serializers.serialize(
        object.energyCost,
        specifiedType: const FullType.nullable(EnergyCostBreakdown),
      );
    }
    if (object.imageCost != null) {
      yield r'image_cost';
      yield serializers.serialize(
        object.imageCost,
        specifiedType: const FullType.nullable(ImageCostBreakdown),
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
    yield r'status';
    yield serializers.serialize(
      object.status,
      specifiedType: const FullType(CostStatus),
    );
    if (object.tokenCost != null) {
      yield r'token_cost';
      yield serializers.serialize(
        object.tokenCost,
        specifiedType: const FullType.nullable(TokenCostBreakdown),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    CostBreakdown object, {
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
    required CostBreakdownBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'currency':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(Currency),
          ) as Currency?;
          if (valueDes == null) continue;
          result.currency = valueDes;
          break;
        case r'energy_cost':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(EnergyCostBreakdown),
          ) as EnergyCostBreakdown?;
          if (valueDes == null) continue;
          result.energyCost.replace(valueDes);
          break;
        case r'image_cost':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(ImageCostBreakdown),
          ) as ImageCostBreakdown?;
          if (valueDes == null) continue;
          result.imageCost.replace(valueDes);
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
        case r'status':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(CostStatus),
          ) as CostStatus;
          result.status = valueDes;
          break;
        case r'token_cost':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(TokenCostBreakdown),
          ) as TokenCostBreakdown?;
          if (valueDes == null) continue;
          result.tokenCost.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  CostBreakdown deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = CostBreakdownBuilder();
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
