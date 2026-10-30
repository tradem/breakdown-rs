// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:breakdown_api/src/model/currency.dart';
import 'package:breakdown_api/src/model/cost_total_status.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'cost_total.g.dart';

/// The figure the user pays: the sum over a job's priced cost components (issue #768). `total_nano` is present exactly when [`Self::status`] is [`CostTotalStatus::Known`].
///
/// Properties:
/// * [currency]
/// * [status]
/// * [totalNano]
@BuiltValue()
abstract class CostTotal implements Built<CostTotal, CostTotalBuilder> {
  @BuiltValueField(wireName: r'currency')
  Currency? get currency;
  // enum currencyEnum {  USD,  EUR,  };

  @BuiltValueField(wireName: r'status')
  CostTotalStatus get status;
  // enum statusEnum {  known,  incomplete,  mixed_currency,  unknown,  };

  @BuiltValueField(wireName: r'total_nano')
  int? get totalNano;

  CostTotal._();

  factory CostTotal([void updates(CostTotalBuilder b)]) = _$CostTotal;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(CostTotalBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<CostTotal> get serializer => _$CostTotalSerializer();
}

class _$CostTotalSerializer implements PrimitiveSerializer<CostTotal> {
  @override
  final Iterable<Type> types = const [CostTotal, _$CostTotal];

  @override
  final String wireName = r'CostTotal';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    CostTotal object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.currency != null) {
      yield r'currency';
      yield serializers.serialize(
        object.currency,
        specifiedType: const FullType.nullable(Currency),
      );
    }
    yield r'status';
    yield serializers.serialize(
      object.status,
      specifiedType: const FullType(CostTotalStatus),
    );
    if (object.totalNano != null) {
      yield r'total_nano';
      yield serializers.serialize(
        object.totalNano,
        specifiedType: const FullType.nullable(int),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    CostTotal object, {
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
    required CostTotalBuilder result,
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
        case r'status':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(CostTotalStatus),
          ) as CostTotalStatus;
          result.status = valueDes;
          break;
        case r'total_nano':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(int),
          ) as int?;
          if (valueDes == null) continue;
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
  CostTotal deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = CostTotalBuilder();
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
