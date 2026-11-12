// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:breakdown_api/src/model/apply_mapping_decision_one_of_update.dart';
import 'package:breakdown_api/src/model/apply_mapping_decision_one_of.dart';
import 'dart:core';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';
import 'package:one_of/one_of.dart';

part 'apply_mapping_decision.g.dart';

/// ApplyMappingDecision
///
/// Properties:
/// * [decisionUpdate]
@BuiltValue()
abstract class ApplyMappingDecision
    implements Built<ApplyMappingDecision, ApplyMappingDecisionBuilder> {
  /// One Of [ApplyMappingDecisionOneOf], [String]
  OneOf get oneOf;

  ApplyMappingDecision._();

  factory ApplyMappingDecision([void updates(ApplyMappingDecisionBuilder b)]) =
      _$ApplyMappingDecision;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ApplyMappingDecisionBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ApplyMappingDecision> get serializer =>
      _$ApplyMappingDecisionSerializer();
}

class _$ApplyMappingDecisionSerializer
    implements PrimitiveSerializer<ApplyMappingDecision> {
  @override
  final Iterable<Type> types = const [
    ApplyMappingDecision,
    _$ApplyMappingDecision
  ];

  @override
  final String wireName = r'ApplyMappingDecision';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ApplyMappingDecision object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {}

  @override
  Object serialize(
    Serializers serializers,
    ApplyMappingDecision object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final oneOf = object.oneOf;
    return serializers.serialize(oneOf.value,
        specifiedType: FullType(oneOf.valueType))!;
  }

  @override
  ApplyMappingDecision deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ApplyMappingDecisionBuilder();
    Object? oneOfDataSrc;
    final targetType = const FullType(OneOf, [
      FullType(String),
      FullType(ApplyMappingDecisionOneOf),
    ]);
    oneOfDataSrc = serialized;
    result.oneOf = serializers.deserialize(oneOfDataSrc,
        specifiedType: targetType) as OneOf;
    return result.build();
  }
}
