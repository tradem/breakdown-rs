// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:breakdown_api/src/model/shooting_day_source_one_of_ai_extracted.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'shooting_day_source_one_of.g.dart';

/// ShootingDaySourceOneOf
///
/// Properties:
/// * [aiExtracted]
@BuiltValue()
abstract class ShootingDaySourceOneOf
    implements Built<ShootingDaySourceOneOf, ShootingDaySourceOneOfBuilder> {
  @BuiltValueField(wireName: r'AiExtracted')
  ShootingDaySourceOneOfAiExtracted get aiExtracted;

  ShootingDaySourceOneOf._();

  factory ShootingDaySourceOneOf(
          [void updates(ShootingDaySourceOneOfBuilder b)]) =
      _$ShootingDaySourceOneOf;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ShootingDaySourceOneOfBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ShootingDaySourceOneOf> get serializer =>
      _$ShootingDaySourceOneOfSerializer();
}

class _$ShootingDaySourceOneOfSerializer
    implements PrimitiveSerializer<ShootingDaySourceOneOf> {
  @override
  final Iterable<Type> types = const [
    ShootingDaySourceOneOf,
    _$ShootingDaySourceOneOf
  ];

  @override
  final String wireName = r'ShootingDaySourceOneOf';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ShootingDaySourceOneOf object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'AiExtracted';
    yield serializers.serialize(
      object.aiExtracted,
      specifiedType: const FullType(ShootingDaySourceOneOfAiExtracted),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    ShootingDaySourceOneOf object, {
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
    required ShootingDaySourceOneOfBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'AiExtracted':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(ShootingDaySourceOneOfAiExtracted),
          ) as ShootingDaySourceOneOfAiExtracted;
          result.aiExtracted.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  ShootingDaySourceOneOf deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ShootingDaySourceOneOfBuilder();
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
