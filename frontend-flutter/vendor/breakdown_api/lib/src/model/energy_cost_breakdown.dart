// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'energy_cost_breakdown.g.dart';

/// Hardware-energy cost of the **extraction** component of one import, in nano-units. Populated only when the job recorded energy telemetry for the extraction calls and the extraction model carries an energy rate.  Decision-Model energy is reported (and priced) on [`DecisionCostBreakdown`] instead (issue #768).  Every figure sums the job's **requests**, each capped on its own (issue #794): a provider that caps energy by token cost does so per request, so `effective_capped_nano = Σ_calls min(raw_i, token_i)`. Capping the summed figures instead would report `min(Σ raw_i, Σ token_i)`, an upper bound that can only overstate what was billed.
///
/// Properties:
/// * [cappedByTokenCost] - Whether the token-cost cap reduced **any** of the requests.
/// * [effectiveCappedNano] - The cost that counts: `Σ_calls min(raw_i, token_i)` when the provider caps energy by token cost (Neuralwatt surge protection, applied per request), otherwise `raw_energy_nano`.
/// * [energyMillijoules]
/// * [rateNanoPerKwh]
/// * [rawEnergyNano] - Uncapped energy cost, summed over the requests (`Σ_i mJ_i × rate / 3.6e9`, each term half-up rounded).
@BuiltValue()
abstract class EnergyCostBreakdown
    implements Built<EnergyCostBreakdown, EnergyCostBreakdownBuilder> {
  /// Whether the token-cost cap reduced **any** of the requests.
  @BuiltValueField(wireName: r'capped_by_token_cost')
  bool get cappedByTokenCost;

  /// The cost that counts: `Σ_calls min(raw_i, token_i)` when the provider caps energy by token cost (Neuralwatt surge protection, applied per request), otherwise `raw_energy_nano`.
  @BuiltValueField(wireName: r'effective_capped_nano')
  int get effectiveCappedNano;

  @BuiltValueField(wireName: r'energy_millijoules')
  int get energyMillijoules;

  @BuiltValueField(wireName: r'rate_nano_per_kwh')
  int get rateNanoPerKwh;

  /// Uncapped energy cost, summed over the requests (`Σ_i mJ_i × rate / 3.6e9`, each term half-up rounded).
  @BuiltValueField(wireName: r'raw_energy_nano')
  int get rawEnergyNano;

  EnergyCostBreakdown._();

  factory EnergyCostBreakdown([void updates(EnergyCostBreakdownBuilder b)]) =
      _$EnergyCostBreakdown;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(EnergyCostBreakdownBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<EnergyCostBreakdown> get serializer =>
      _$EnergyCostBreakdownSerializer();
}

class _$EnergyCostBreakdownSerializer
    implements PrimitiveSerializer<EnergyCostBreakdown> {
  @override
  final Iterable<Type> types = const [
    EnergyCostBreakdown,
    _$EnergyCostBreakdown
  ];

  @override
  final String wireName = r'EnergyCostBreakdown';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    EnergyCostBreakdown object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'capped_by_token_cost';
    yield serializers.serialize(
      object.cappedByTokenCost,
      specifiedType: const FullType(bool),
    );
    yield r'effective_capped_nano';
    yield serializers.serialize(
      object.effectiveCappedNano,
      specifiedType: const FullType(int),
    );
    yield r'energy_millijoules';
    yield serializers.serialize(
      object.energyMillijoules,
      specifiedType: const FullType(int),
    );
    yield r'rate_nano_per_kwh';
    yield serializers.serialize(
      object.rateNanoPerKwh,
      specifiedType: const FullType(int),
    );
    yield r'raw_energy_nano';
    yield serializers.serialize(
      object.rawEnergyNano,
      specifiedType: const FullType(int),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    EnergyCostBreakdown object, {
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
    required EnergyCostBreakdownBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'capped_by_token_cost':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.cappedByTokenCost = valueDes;
          break;
        case r'effective_capped_nano':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.effectiveCappedNano = valueDes;
          break;
        case r'energy_millijoules':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.energyMillijoules = valueDes;
          break;
        case r'rate_nano_per_kwh':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.rateNanoPerKwh = valueDes;
          break;
        case r'raw_energy_nano':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.rawEnergyNano = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  EnergyCostBreakdown deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = EnergyCostBreakdownBuilder();
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
