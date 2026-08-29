// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'photo_binding_one_of_costume.g.dart';

/// Costume (Anprobe) photo — taken before the shoot for planning.
///
/// Properties:
/// * [costumeId]
@BuiltValue()
abstract class PhotoBindingOneOfCostume
    implements
        Built<PhotoBindingOneOfCostume, PhotoBindingOneOfCostumeBuilder> {
  @BuiltValueField(wireName: r'costume_id')
  String get costumeId;

  PhotoBindingOneOfCostume._();

  factory PhotoBindingOneOfCostume(
          [void updates(PhotoBindingOneOfCostumeBuilder b)]) =
      _$PhotoBindingOneOfCostume;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(PhotoBindingOneOfCostumeBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<PhotoBindingOneOfCostume> get serializer =>
      _$PhotoBindingOneOfCostumeSerializer();
}

class _$PhotoBindingOneOfCostumeSerializer
    implements PrimitiveSerializer<PhotoBindingOneOfCostume> {
  @override
  final Iterable<Type> types = const [
    PhotoBindingOneOfCostume,
    _$PhotoBindingOneOfCostume
  ];

  @override
  final String wireName = r'PhotoBindingOneOfCostume';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    PhotoBindingOneOfCostume object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'costume_id';
    yield serializers.serialize(
      object.costumeId,
      specifiedType: const FullType(String),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    PhotoBindingOneOfCostume object, {
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
    required PhotoBindingOneOfCostumeBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'costume_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.costumeId = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  PhotoBindingOneOfCostume deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = PhotoBindingOneOfCostumeBuilder();
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
