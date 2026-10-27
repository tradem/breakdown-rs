// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:breakdown_api/src/model/photo_binding_one_of2_continuity.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'photo_binding_one_of2.g.dart';

/// Continuity (Anschluss) photo — taken during the shoot.
///
/// Properties:
/// * [continuity]
@BuiltValue()
abstract class PhotoBindingOneOf2
    implements Built<PhotoBindingOneOf2, PhotoBindingOneOf2Builder> {
  @BuiltValueField(wireName: r'continuity')
  PhotoBindingOneOf2Continuity get continuity;

  PhotoBindingOneOf2._();

  factory PhotoBindingOneOf2([void updates(PhotoBindingOneOf2Builder b)]) =
      _$PhotoBindingOneOf2;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(PhotoBindingOneOf2Builder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<PhotoBindingOneOf2> get serializer =>
      _$PhotoBindingOneOf2Serializer();
}

class _$PhotoBindingOneOf2Serializer
    implements PrimitiveSerializer<PhotoBindingOneOf2> {
  @override
  final Iterable<Type> types = const [PhotoBindingOneOf2, _$PhotoBindingOneOf2];

  @override
  final String wireName = r'PhotoBindingOneOf2';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    PhotoBindingOneOf2 object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'continuity';
    yield serializers.serialize(
      object.continuity,
      specifiedType: const FullType(PhotoBindingOneOf2Continuity),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    PhotoBindingOneOf2 object, {
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
    required PhotoBindingOneOf2Builder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'continuity':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(PhotoBindingOneOf2Continuity),
          ) as PhotoBindingOneOf2Continuity;
          result.continuity.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  PhotoBindingOneOf2 deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = PhotoBindingOneOf2Builder();
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
