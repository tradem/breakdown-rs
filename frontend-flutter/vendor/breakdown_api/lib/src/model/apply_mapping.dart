// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:breakdown_api/src/model/apply_mapping_decision.dart';
import 'package:built_collection/built_collection.dart';
import 'package:breakdown_api/src/model/costume_decision.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'apply_mapping.g.dart';

/// User decision for one draft row. A create decision leaves the aggregate id absent; an update decision carries the existing id and optimistic version.
///
/// Properties:
/// * [costumeDecisions] - Per-costume-row decisions of this draft row. Absent ordinals default to accepted, so a request written before this field existed (or one where the reviewer touched nothing) still applies everything that was extracted.
/// * [decision]
/// * [draftRef]
@BuiltValue()
abstract class ApplyMapping
    implements Built<ApplyMapping, ApplyMappingBuilder> {
  /// Per-costume-row decisions of this draft row. Absent ordinals default to accepted, so a request written before this field existed (or one where the reviewer touched nothing) still applies everything that was extracted.
  @BuiltValueField(wireName: r'costume_decisions')
  BuiltList<CostumeDecision>? get costumeDecisions;

  @BuiltValueField(wireName: r'decision')
  ApplyMappingDecision get decision;

  @BuiltValueField(wireName: r'draft_ref')
  String get draftRef;

  ApplyMapping._();

  factory ApplyMapping([void updates(ApplyMappingBuilder b)]) = _$ApplyMapping;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ApplyMappingBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ApplyMapping> get serializer => _$ApplyMappingSerializer();
}

class _$ApplyMappingSerializer implements PrimitiveSerializer<ApplyMapping> {
  @override
  final Iterable<Type> types = const [ApplyMapping, _$ApplyMapping];

  @override
  final String wireName = r'ApplyMapping';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ApplyMapping object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.costumeDecisions != null) {
      yield r'costume_decisions';
      yield serializers.serialize(
        object.costumeDecisions,
        specifiedType: const FullType(BuiltList, [FullType(CostumeDecision)]),
      );
    }
    yield r'decision';
    yield serializers.serialize(
      object.decision,
      specifiedType: const FullType(ApplyMappingDecision),
    );
    yield r'draft_ref';
    yield serializers.serialize(
      object.draftRef,
      specifiedType: const FullType(String),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    ApplyMapping object, {
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
    required ApplyMappingBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'costume_decisions':
          final valueDes = serializers.deserialize(
            value,
            specifiedType:
                const FullType.nullable(BuiltList, [FullType(CostumeDecision)]),
          ) as BuiltList<CostumeDecision>?;
          if (valueDes == null) continue;
          result.costumeDecisions.replace(valueDes);
          break;
        case r'decision':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(ApplyMappingDecision),
          ) as ApplyMappingDecision;
          result.decision.replace(valueDes);
          break;
        case r'draft_ref':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.draftRef = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  ApplyMapping deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ApplyMappingBuilder();
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
