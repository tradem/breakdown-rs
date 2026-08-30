// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:breakdown_api/src/model/photo_binding_one_of.dart';
import 'package:breakdown_api/src/model/photo_binding_one_of1.dart';
import 'package:breakdown_api/src/model/photo_binding_one_of1_continuity.dart';
import 'package:breakdown_api/src/model/photo_binding_one_of_costume.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';
import 'package:one_of/one_of.dart';

part 'photo_binding.g.dart';

/// Discriminates what a photo is attached to.  `Costume` — Anprobe/planning photo (taken before the shoot). `Continuity` — continuity photo taken during the shoot; `costume_id` is `Option` so prop-only continuity shots are permitted (the edge case).  The `Default` implementation returns `Costume { costume_id: Uuid::nil() }` so that historical `PhotoUploaded` events (pre-binding) deserialise as costume photos, matching the backward-compat requirement.
///
/// Properties:
/// * [costume]
/// * [continuity]
@BuiltValue()
abstract class PhotoBinding
    implements Built<PhotoBinding, PhotoBindingBuilder> {
  /// One Of [PhotoBindingOneOf], [PhotoBindingOneOf1]
  OneOf get oneOf;

  PhotoBinding._();

  factory PhotoBinding([void updates(PhotoBindingBuilder b)]) = _$PhotoBinding;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(PhotoBindingBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<PhotoBinding> get serializer => _$PhotoBindingSerializer();
}

class _$PhotoBindingSerializer implements PrimitiveSerializer<PhotoBinding> {
  @override
  final Iterable<Type> types = const [PhotoBinding, _$PhotoBinding];

  @override
  final String wireName = r'PhotoBinding';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    PhotoBinding object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {}

  @override
  Object serialize(
    Serializers serializers,
    PhotoBinding object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final oneOf = object.oneOf;
    return serializers.serialize(oneOf.value,
        specifiedType: FullType(oneOf.valueType))!;
  }

  @override
  PhotoBinding deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = PhotoBindingBuilder();
    Object? oneOfDataSrc;
    final targetType = const FullType(OneOf, [
      FullType(PhotoBindingOneOf),
      FullType(PhotoBindingOneOf1),
    ]);
    oneOfDataSrc = serialized;
    result.oneOf = serializers.deserialize(oneOfDataSrc,
        specifiedType: targetType) as OneOf;
    return result.build();
  }
}
