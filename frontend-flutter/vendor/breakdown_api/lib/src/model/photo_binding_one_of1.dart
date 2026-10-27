// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:breakdown_api/src/model/photo_binding_one_of1_outfit.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'photo_binding_one_of1.g.dart';

/// Outfit (Anprobe) photo — a composed look, taken before the shoot.
///
/// Properties:
/// * [outfit]
@BuiltValue()
abstract class PhotoBindingOneOf1
    implements Built<PhotoBindingOneOf1, PhotoBindingOneOf1Builder> {
  @BuiltValueField(wireName: r'outfit')
  PhotoBindingOneOf1Outfit get outfit;

  PhotoBindingOneOf1._();

  factory PhotoBindingOneOf1([void updates(PhotoBindingOneOf1Builder b)]) =
      _$PhotoBindingOneOf1;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(PhotoBindingOneOf1Builder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<PhotoBindingOneOf1> get serializer =>
      _$PhotoBindingOneOf1Serializer();
}

class _$PhotoBindingOneOf1Serializer
    implements PrimitiveSerializer<PhotoBindingOneOf1> {
  @override
  final Iterable<Type> types = const [PhotoBindingOneOf1, _$PhotoBindingOneOf1];

  @override
  final String wireName = r'PhotoBindingOneOf1';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    PhotoBindingOneOf1 object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'outfit';
    yield serializers.serialize(
      object.outfit,
      specifiedType: const FullType(PhotoBindingOneOf1Outfit),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    PhotoBindingOneOf1 object, {
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
    required PhotoBindingOneOf1Builder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'outfit':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(PhotoBindingOneOf1Outfit),
          ) as PhotoBindingOneOf1Outfit;
          result.outfit.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  PhotoBindingOneOf1 deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = PhotoBindingOneOf1Builder();
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
