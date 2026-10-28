// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:breakdown_api/src/model/apply_mapping_decision.dart';
import 'package:built_collection/built_collection.dart';
import 'package:breakdown_api/src/model/outfit_decision.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'apply_mapping.g.dart';

/// User decision for one draft row. A create decision leaves the aggregate id absent; an update decision carries the existing id and optimistic version.
///
/// Properties:
/// * [decision]
/// * [draftRef]
/// * [outfitDecisions] - Per-outfit-row decisions of this draft row. Absent ordinals default to accepted, so a request written before this field existed (or one where the reviewer touched nothing) still applies everything that was extracted.  `costume_decisions` is accepted as an alias (OpenSpec change `ai-import-outfit-and-pieces`): the pre-rename client sends the same `{ordinal, accepted}` items under the old name, and silently dropping them would turn a reviewer's rejection into an applied outfit — a fail-open on the one decision surface that must never be ignored.
@BuiltValue()
abstract class ApplyMapping
    implements Built<ApplyMapping, ApplyMappingBuilder> {
  @BuiltValueField(wireName: r'decision')
  ApplyMappingDecision get decision;

  @BuiltValueField(wireName: r'draft_ref')
  String get draftRef;

  /// Per-outfit-row decisions of this draft row. Absent ordinals default to accepted, so a request written before this field existed (or one where the reviewer touched nothing) still applies everything that was extracted.  `costume_decisions` is accepted as an alias (OpenSpec change `ai-import-outfit-and-pieces`): the pre-rename client sends the same `{ordinal, accepted}` items under the old name, and silently dropping them would turn a reviewer's rejection into an applied outfit — a fail-open on the one decision surface that must never be ignored.
  @BuiltValueField(wireName: r'outfit_decisions')
  BuiltList<OutfitDecision>? get outfitDecisions;

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
    if (object.outfitDecisions != null) {
      yield r'outfit_decisions';
      yield serializers.serialize(
        object.outfitDecisions,
        specifiedType: const FullType(BuiltList, [FullType(OutfitDecision)]),
      );
    }
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
        case r'outfit_decisions':
          final valueDes = serializers.deserialize(
            value,
            specifiedType:
                const FullType.nullable(BuiltList, [FullType(OutfitDecision)]),
          ) as BuiltList<OutfitDecision>?;
          if (valueDes == null) continue;
          result.outfitDecisions.replace(valueDes);
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
