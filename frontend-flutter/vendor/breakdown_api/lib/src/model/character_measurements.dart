// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'character_measurements.g.dart';

/// Payload for measurement fields updated as a God-Command.
///
/// Properties:
/// * [chest]
/// * [hatSize]
/// * [height]
/// * [hips]
/// * [shoeSize]
/// * [waist]
/// * [weight]
@BuiltValue()
abstract class CharacterMeasurements
    implements Built<CharacterMeasurements, CharacterMeasurementsBuilder> {
  @BuiltValueField(wireName: r'chest')
  String? get chest;

  @BuiltValueField(wireName: r'hat_size')
  String? get hatSize;

  @BuiltValueField(wireName: r'height')
  String? get height;

  @BuiltValueField(wireName: r'hips')
  String? get hips;

  @BuiltValueField(wireName: r'shoe_size')
  String? get shoeSize;

  @BuiltValueField(wireName: r'waist')
  String? get waist;

  @BuiltValueField(wireName: r'weight')
  String? get weight;

  CharacterMeasurements._();

  factory CharacterMeasurements(
      [void updates(CharacterMeasurementsBuilder b)]) = _$CharacterMeasurements;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(CharacterMeasurementsBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<CharacterMeasurements> get serializer =>
      _$CharacterMeasurementsSerializer();
}

class _$CharacterMeasurementsSerializer
    implements PrimitiveSerializer<CharacterMeasurements> {
  @override
  final Iterable<Type> types = const [
    CharacterMeasurements,
    _$CharacterMeasurements
  ];

  @override
  final String wireName = r'CharacterMeasurements';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    CharacterMeasurements object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.chest != null) {
      yield r'chest';
      yield serializers.serialize(
        object.chest,
        specifiedType: const FullType.nullable(String),
      );
    }
    if (object.hatSize != null) {
      yield r'hat_size';
      yield serializers.serialize(
        object.hatSize,
        specifiedType: const FullType.nullable(String),
      );
    }
    if (object.height != null) {
      yield r'height';
      yield serializers.serialize(
        object.height,
        specifiedType: const FullType.nullable(String),
      );
    }
    if (object.hips != null) {
      yield r'hips';
      yield serializers.serialize(
        object.hips,
        specifiedType: const FullType.nullable(String),
      );
    }
    if (object.shoeSize != null) {
      yield r'shoe_size';
      yield serializers.serialize(
        object.shoeSize,
        specifiedType: const FullType.nullable(String),
      );
    }
    if (object.waist != null) {
      yield r'waist';
      yield serializers.serialize(
        object.waist,
        specifiedType: const FullType.nullable(String),
      );
    }
    if (object.weight != null) {
      yield r'weight';
      yield serializers.serialize(
        object.weight,
        specifiedType: const FullType.nullable(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    CharacterMeasurements object, {
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
    required CharacterMeasurementsBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'chest':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.chest = valueDes;
          break;
        case r'hat_size':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.hatSize = valueDes;
          break;
        case r'height':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.height = valueDes;
          break;
        case r'hips':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.hips = valueDes;
          break;
        case r'shoe_size':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.shoeSize = valueDes;
          break;
        case r'waist':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.waist = valueDes;
          break;
        case r'weight':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.weight = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  CharacterMeasurements deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = CharacterMeasurementsBuilder();
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
