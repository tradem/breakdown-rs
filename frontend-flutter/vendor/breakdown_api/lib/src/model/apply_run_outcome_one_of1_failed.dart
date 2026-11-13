// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'apply_run_outcome_one_of1_failed.g.dart';

/// The run stopped on an error the client can branch on.
///
/// Properties:
/// * [code] - Stable problem code (e.g. `ai-import.apply-missing-shooting-day-group`).
@BuiltValue()
abstract class ApplyRunOutcomeOneOf1Failed
    implements
        Built<ApplyRunOutcomeOneOf1Failed, ApplyRunOutcomeOneOf1FailedBuilder> {
  /// Stable problem code (e.g. `ai-import.apply-missing-shooting-day-group`).
  @BuiltValueField(wireName: r'code')
  String get code;

  ApplyRunOutcomeOneOf1Failed._();

  factory ApplyRunOutcomeOneOf1Failed(
          [void updates(ApplyRunOutcomeOneOf1FailedBuilder b)]) =
      _$ApplyRunOutcomeOneOf1Failed;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ApplyRunOutcomeOneOf1FailedBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ApplyRunOutcomeOneOf1Failed> get serializer =>
      _$ApplyRunOutcomeOneOf1FailedSerializer();
}

class _$ApplyRunOutcomeOneOf1FailedSerializer
    implements PrimitiveSerializer<ApplyRunOutcomeOneOf1Failed> {
  @override
  final Iterable<Type> types = const [
    ApplyRunOutcomeOneOf1Failed,
    _$ApplyRunOutcomeOneOf1Failed
  ];

  @override
  final String wireName = r'ApplyRunOutcomeOneOf1Failed';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ApplyRunOutcomeOneOf1Failed object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'code';
    yield serializers.serialize(
      object.code,
      specifiedType: const FullType(String),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    ApplyRunOutcomeOneOf1Failed object, {
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
    required ApplyRunOutcomeOneOf1FailedBuilder result,
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
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  ApplyRunOutcomeOneOf1Failed deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ApplyRunOutcomeOneOf1FailedBuilder();
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
