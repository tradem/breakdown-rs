// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'apply_run_outcome_one_of1.g.dart';

/// The run stopped on an error the client can branch on.
///
/// Properties:
/// * [code] - Stable problem code (e.g. `ai-import.apply-missing-shooting-day-group`).
/// * [outcome]
@BuiltValue()
abstract class ApplyRunOutcomeOneOf1
    implements Built<ApplyRunOutcomeOneOf1, ApplyRunOutcomeOneOf1Builder> {
  /// Stable problem code (e.g. `ai-import.apply-missing-shooting-day-group`).
  @BuiltValueField(wireName: r'code')
  String get code;

  @BuiltValueField(wireName: r'outcome')
  ApplyRunOutcomeOneOf1OutcomeEnum get outcome;
  // enum outcomeEnum {  failed,  };

  ApplyRunOutcomeOneOf1._();

  factory ApplyRunOutcomeOneOf1(
      [void updates(ApplyRunOutcomeOneOf1Builder b)]) = _$ApplyRunOutcomeOneOf1;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ApplyRunOutcomeOneOf1Builder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ApplyRunOutcomeOneOf1> get serializer =>
      _$ApplyRunOutcomeOneOf1Serializer();
}

class _$ApplyRunOutcomeOneOf1Serializer
    implements PrimitiveSerializer<ApplyRunOutcomeOneOf1> {
  @override
  final Iterable<Type> types = const [
    ApplyRunOutcomeOneOf1,
    _$ApplyRunOutcomeOneOf1
  ];

  @override
  final String wireName = r'ApplyRunOutcomeOneOf1';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ApplyRunOutcomeOneOf1 object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'code';
    yield serializers.serialize(
      object.code,
      specifiedType: const FullType(String),
    );
    yield r'outcome';
    yield serializers.serialize(
      object.outcome,
      specifiedType: const FullType(ApplyRunOutcomeOneOf1OutcomeEnum),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    ApplyRunOutcomeOneOf1 object, {
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
    required ApplyRunOutcomeOneOf1Builder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'code':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.code = valueDes;
          break;
        case r'outcome':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(ApplyRunOutcomeOneOf1OutcomeEnum),
          ) as ApplyRunOutcomeOneOf1OutcomeEnum;
          result.outcome = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  ApplyRunOutcomeOneOf1 deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ApplyRunOutcomeOneOf1Builder();
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

class ApplyRunOutcomeOneOf1OutcomeEnum extends EnumClass {
  @BuiltValueEnumConst(wireName: r'failed')
  static const ApplyRunOutcomeOneOf1OutcomeEnum failed =
      _$applyRunOutcomeOneOf1OutcomeEnum_failed;

  static Serializer<ApplyRunOutcomeOneOf1OutcomeEnum> get serializer =>
      _$applyRunOutcomeOneOf1OutcomeEnumSerializer;

  const ApplyRunOutcomeOneOf1OutcomeEnum._(String name) : super(name);

  static BuiltSet<ApplyRunOutcomeOneOf1OutcomeEnum> get values =>
      _$applyRunOutcomeOneOf1OutcomeEnumValues;
  static ApplyRunOutcomeOneOf1OutcomeEnum valueOf(String name) =>
      _$applyRunOutcomeOneOf1OutcomeEnumValueOf(name);
}
