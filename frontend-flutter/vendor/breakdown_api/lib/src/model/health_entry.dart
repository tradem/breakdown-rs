// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:breakdown_api/src/model/health_status.dart';
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'health_entry.g.dart';

/// Result of one dependency check.
///
/// Properties:
/// * [description] - Human-readable failure/success note (static text — never raw error detail, which could leak internal topology).
/// * [durationMs] - Wall-clock time the check took, in milliseconds.
/// * [status]
/// * [tags] - Free-form tags (`ready`, `live`, …) for probe selection.
@BuiltValue()
abstract class HealthEntry implements Built<HealthEntry, HealthEntryBuilder> {
  /// Human-readable failure/success note (static text — never raw error detail, which could leak internal topology).
  @BuiltValueField(wireName: r'description')
  String? get description;

  /// Wall-clock time the check took, in milliseconds.
  @BuiltValueField(wireName: r'duration_ms')
  int get durationMs;

  @BuiltValueField(wireName: r'status')
  HealthStatus get status;
  // enum statusEnum {  Healthy,  Degraded,  Unhealthy,  };

  /// Free-form tags (`ready`, `live`, …) for probe selection.
  @BuiltValueField(wireName: r'tags')
  BuiltList<String> get tags;

  HealthEntry._();

  factory HealthEntry([void updates(HealthEntryBuilder b)]) = _$HealthEntry;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(HealthEntryBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<HealthEntry> get serializer => _$HealthEntrySerializer();
}

class _$HealthEntrySerializer implements PrimitiveSerializer<HealthEntry> {
  @override
  final Iterable<Type> types = const [HealthEntry, _$HealthEntry];

  @override
  final String wireName = r'HealthEntry';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    HealthEntry object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.description != null) {
      yield r'description';
      yield serializers.serialize(
        object.description,
        specifiedType: const FullType.nullable(String),
      );
    }
    yield r'duration_ms';
    yield serializers.serialize(
      object.durationMs,
      specifiedType: const FullType(int),
    );
    yield r'status';
    yield serializers.serialize(
      object.status,
      specifiedType: const FullType(HealthStatus),
    );
    yield r'tags';
    yield serializers.serialize(
      object.tags,
      specifiedType: const FullType(BuiltList, [FullType(String)]),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    HealthEntry object, {
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
    required HealthEntryBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'description':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.description = valueDes;
          break;
        case r'duration_ms':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.durationMs = valueDes;
          break;
        case r'status':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(HealthStatus),
          ) as HealthStatus;
          result.status = valueDes;
          break;
        case r'tags':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(String)]),
          ) as BuiltList<String>;
          result.tags.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  HealthEntry deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = HealthEntryBuilder();
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
