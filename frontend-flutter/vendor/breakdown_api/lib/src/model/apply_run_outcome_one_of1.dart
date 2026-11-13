// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:breakdown_api/src/model/apply_run_outcome_one_of1_failed.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'apply_run_outcome_one_of1.g.dart';

/// The run stopped on an error the client can branch on.
///
/// Properties:
/// * [failed]
@BuiltValue()
abstract class ApplyRunOutcomeOneOf1
    implements Built<ApplyRunOutcomeOneOf1, ApplyRunOutcomeOneOf1Builder> {
  @BuiltValueField(wireName: r'failed')
  ApplyRunOutcomeOneOf1Failed get failed;

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
    yield r'failed';
    yield serializers.serialize(
      object.failed,
      specifiedType: const FullType(ApplyRunOutcomeOneOf1Failed),
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
        case r'failed':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(ApplyRunOutcomeOneOf1Failed),
          ) as ApplyRunOutcomeOneOf1Failed;
          result.failed.replace(valueDes);
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
