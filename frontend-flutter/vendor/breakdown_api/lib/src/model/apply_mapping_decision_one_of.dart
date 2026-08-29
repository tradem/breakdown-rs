// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:breakdown_api/src/model/apply_mapping_decision_one_of_update.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'apply_mapping_decision_one_of.g.dart';

/// ApplyMappingDecisionOneOf
///
/// Properties:
/// * [decisionUpdate]
@BuiltValue()
abstract class ApplyMappingDecisionOneOf
    implements
        Built<ApplyMappingDecisionOneOf, ApplyMappingDecisionOneOfBuilder> {
  @BuiltValueField(wireName: r'Update')
  ApplyMappingDecisionOneOfUpdate get decisionUpdate;

  ApplyMappingDecisionOneOf._();

  factory ApplyMappingDecisionOneOf(
          [void updates(ApplyMappingDecisionOneOfBuilder b)]) =
      _$ApplyMappingDecisionOneOf;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ApplyMappingDecisionOneOfBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ApplyMappingDecisionOneOf> get serializer =>
      _$ApplyMappingDecisionOneOfSerializer();
}

class _$ApplyMappingDecisionOneOfSerializer
    implements PrimitiveSerializer<ApplyMappingDecisionOneOf> {
  @override
  final Iterable<Type> types = const [
    ApplyMappingDecisionOneOf,
    _$ApplyMappingDecisionOneOf
  ];

  @override
  final String wireName = r'ApplyMappingDecisionOneOf';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ApplyMappingDecisionOneOf object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'Update';
    yield serializers.serialize(
      object.decisionUpdate,
      specifiedType: const FullType(ApplyMappingDecisionOneOfUpdate),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    ApplyMappingDecisionOneOf object, {
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
    required ApplyMappingDecisionOneOfBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'Update':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(ApplyMappingDecisionOneOfUpdate),
          ) as ApplyMappingDecisionOneOfUpdate;
          result.decisionUpdate.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  ApplyMappingDecisionOneOf deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ApplyMappingDecisionOneOfBuilder();
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
