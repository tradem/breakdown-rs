// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'apply_mapping_decision_one_of_update.g.dart';

/// ApplyMappingDecisionOneOfUpdate
///
/// Properties:
/// * [aggregateId]
/// * [version] - Aggregate version for optimistic locking.  The canonical version contract is **1-based**: `AggregateVersion::INITIAL = 1`, and every mutation increments the version by one.  The SierraDB stream version (0-based) is an infrastructure-internal detail. The translation rule is: `domain_version = stream_version + 1` (and inversely `stream_version = domain_version - 1`) which is performed exclusively inside `crates::infra` at the `*Commands` adapter boundary. `core` does not reference `stream_version`, `ExpectedVersion`, or `CurrentVersion`.
@BuiltValue()
abstract class ApplyMappingDecisionOneOfUpdate
    implements
        Built<ApplyMappingDecisionOneOfUpdate,
            ApplyMappingDecisionOneOfUpdateBuilder> {
  @BuiltValueField(wireName: r'aggregate_id')
  String get aggregateId;

  /// Aggregate version for optimistic locking.  The canonical version contract is **1-based**: `AggregateVersion::INITIAL = 1`, and every mutation increments the version by one.  The SierraDB stream version (0-based) is an infrastructure-internal detail. The translation rule is: `domain_version = stream_version + 1` (and inversely `stream_version = domain_version - 1`) which is performed exclusively inside `crates::infra` at the `*Commands` adapter boundary. `core` does not reference `stream_version`, `ExpectedVersion`, or `CurrentVersion`.
  @BuiltValueField(wireName: r'version')
  int get version;

  ApplyMappingDecisionOneOfUpdate._();

  factory ApplyMappingDecisionOneOfUpdate(
          [void updates(ApplyMappingDecisionOneOfUpdateBuilder b)]) =
      _$ApplyMappingDecisionOneOfUpdate;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ApplyMappingDecisionOneOfUpdateBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ApplyMappingDecisionOneOfUpdate> get serializer =>
      _$ApplyMappingDecisionOneOfUpdateSerializer();
}

class _$ApplyMappingDecisionOneOfUpdateSerializer
    implements PrimitiveSerializer<ApplyMappingDecisionOneOfUpdate> {
  @override
  final Iterable<Type> types = const [
    ApplyMappingDecisionOneOfUpdate,
    _$ApplyMappingDecisionOneOfUpdate
  ];

  @override
  final String wireName = r'ApplyMappingDecisionOneOfUpdate';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ApplyMappingDecisionOneOfUpdate object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'aggregate_id';
    yield serializers.serialize(
      object.aggregateId,
      specifiedType: const FullType(String),
    );
    yield r'version';
    yield serializers.serialize(
      object.version,
      specifiedType: const FullType(int),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    ApplyMappingDecisionOneOfUpdate object, {
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
    required ApplyMappingDecisionOneOfUpdateBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'aggregate_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.aggregateId = valueDes;
          break;
        case r'version':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.version = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  ApplyMappingDecisionOneOfUpdate deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ApplyMappingDecisionOneOfUpdateBuilder();
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
