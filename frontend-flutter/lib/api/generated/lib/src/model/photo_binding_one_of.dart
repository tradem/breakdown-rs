// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:breakdown_api/src/model/photo_binding_one_of_costume.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'photo_binding_one_of.g.dart';

/// Costume (Anprobe) photo — taken before the shoot for planning.
///
/// Properties:
/// * [costume]
@BuiltValue()
abstract class PhotoBindingOneOf
    implements Built<PhotoBindingOneOf, PhotoBindingOneOfBuilder> {
  @BuiltValueField(wireName: r'costume')
  PhotoBindingOneOfCostume get costume;

  PhotoBindingOneOf._();

  factory PhotoBindingOneOf([void updates(PhotoBindingOneOfBuilder b)]) =
      _$PhotoBindingOneOf;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(PhotoBindingOneOfBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<PhotoBindingOneOf> get serializer =>
      _$PhotoBindingOneOfSerializer();
}

class _$PhotoBindingOneOfSerializer
    implements PrimitiveSerializer<PhotoBindingOneOf> {
  @override
  final Iterable<Type> types = const [PhotoBindingOneOf, _$PhotoBindingOneOf];

  @override
  final String wireName = r'PhotoBindingOneOf';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    PhotoBindingOneOf object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'costume';
    yield serializers.serialize(
      object.costume,
      specifiedType: const FullType(PhotoBindingOneOfCostume),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    PhotoBindingOneOf object, {
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
    required PhotoBindingOneOfBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'costume':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(PhotoBindingOneOfCostume),
          ) as PhotoBindingOneOfCostume;
          result.costume.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  PhotoBindingOneOf deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = PhotoBindingOneOfBuilder();
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
