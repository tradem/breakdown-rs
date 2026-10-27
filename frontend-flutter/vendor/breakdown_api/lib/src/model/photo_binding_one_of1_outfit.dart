// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'photo_binding_one_of1_outfit.g.dart';

/// Outfit (Anprobe) photo — a composed look, taken before the shoot.
///
/// Properties:
/// * [outfitId]
@BuiltValue()
abstract class PhotoBindingOneOf1Outfit
    implements
        Built<PhotoBindingOneOf1Outfit, PhotoBindingOneOf1OutfitBuilder> {
  @BuiltValueField(wireName: r'outfit_id')
  String get outfitId;

  PhotoBindingOneOf1Outfit._();

  factory PhotoBindingOneOf1Outfit(
          [void updates(PhotoBindingOneOf1OutfitBuilder b)]) =
      _$PhotoBindingOneOf1Outfit;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(PhotoBindingOneOf1OutfitBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<PhotoBindingOneOf1Outfit> get serializer =>
      _$PhotoBindingOneOf1OutfitSerializer();
}

class _$PhotoBindingOneOf1OutfitSerializer
    implements PrimitiveSerializer<PhotoBindingOneOf1Outfit> {
  @override
  final Iterable<Type> types = const [
    PhotoBindingOneOf1Outfit,
    _$PhotoBindingOneOf1Outfit
  ];

  @override
  final String wireName = r'PhotoBindingOneOf1Outfit';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    PhotoBindingOneOf1Outfit object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'outfit_id';
    yield serializers.serialize(
      object.outfitId,
      specifiedType: const FullType(String),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    PhotoBindingOneOf1Outfit object, {
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
    required PhotoBindingOneOf1OutfitBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'outfit_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.outfitId = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  PhotoBindingOneOf1Outfit deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = PhotoBindingOneOf1OutfitBuilder();
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
