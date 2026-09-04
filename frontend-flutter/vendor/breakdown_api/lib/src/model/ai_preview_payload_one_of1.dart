// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:breakdown_api/src/model/shooting_schedule.dart';
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'ai_preview_payload_one_of1.g.dart';

/// AiPreviewPayloadOneOf1
///
/// Properties:
/// * [data]
/// * [kind]
@BuiltValue()
abstract class AiPreviewPayloadOneOf1
    implements Built<AiPreviewPayloadOneOf1, AiPreviewPayloadOneOf1Builder> {
  @BuiltValueField(wireName: r'data')
  ShootingSchedule get data;

  @BuiltValueField(wireName: r'kind')
  AiPreviewPayloadOneOf1KindEnum get kind;
  // enum kindEnum {  schedule,  };

  AiPreviewPayloadOneOf1._();

  factory AiPreviewPayloadOneOf1(
          [void updates(AiPreviewPayloadOneOf1Builder b)]) =
      _$AiPreviewPayloadOneOf1;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(AiPreviewPayloadOneOf1Builder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<AiPreviewPayloadOneOf1> get serializer =>
      _$AiPreviewPayloadOneOf1Serializer();
}

class _$AiPreviewPayloadOneOf1Serializer
    implements PrimitiveSerializer<AiPreviewPayloadOneOf1> {
  @override
  final Iterable<Type> types = const [
    AiPreviewPayloadOneOf1,
    _$AiPreviewPayloadOneOf1
  ];

  @override
  final String wireName = r'AiPreviewPayloadOneOf1';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    AiPreviewPayloadOneOf1 object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'data';
    yield serializers.serialize(
      object.data,
      specifiedType: const FullType(ShootingSchedule),
    );
    yield r'kind';
    yield serializers.serialize(
      object.kind,
      specifiedType: const FullType(AiPreviewPayloadOneOf1KindEnum),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    AiPreviewPayloadOneOf1 object, {
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
    required AiPreviewPayloadOneOf1Builder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'data':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(ShootingSchedule),
          ) as ShootingSchedule;
          result.data.replace(valueDes);
          break;
        case r'kind':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(AiPreviewPayloadOneOf1KindEnum),
          ) as AiPreviewPayloadOneOf1KindEnum;
          result.kind = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  AiPreviewPayloadOneOf1 deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = AiPreviewPayloadOneOf1Builder();
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

class AiPreviewPayloadOneOf1KindEnum extends EnumClass {
  @BuiltValueEnumConst(wireName: r'schedule')
  static const AiPreviewPayloadOneOf1KindEnum schedule =
      _$aiPreviewPayloadOneOf1KindEnum_schedule;

  static Serializer<AiPreviewPayloadOneOf1KindEnum> get serializer =>
      _$aiPreviewPayloadOneOf1KindEnumSerializer;

  const AiPreviewPayloadOneOf1KindEnum._(String name) : super(name);

  static BuiltSet<AiPreviewPayloadOneOf1KindEnum> get values =>
      _$aiPreviewPayloadOneOf1KindEnumValues;
  static AiPreviewPayloadOneOf1KindEnum valueOf(String name) =>
      _$aiPreviewPayloadOneOf1KindEnumValueOf(name);
}
