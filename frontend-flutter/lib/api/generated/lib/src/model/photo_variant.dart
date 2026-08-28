// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'photo_variant.g.dart';

/// The three image variants stored for each photo.  `Original` is the re-encoded, upright, EXIF-stripped source image (quality ~95). `Thumb` is a ~200×200 JPEG (quality 80). `Medium` is an ~800×800 JPEG (quality 85). Adding a new variant is additive — only the enum gains a variant and the saga gains a generation step.
class PhotoVariant extends EnumClass {
  @BuiltValueEnumConst(wireName: r'Original')
  static const PhotoVariant original = _$original;
  @BuiltValueEnumConst(wireName: r'Thumb')
  static const PhotoVariant thumb = _$thumb;
  @BuiltValueEnumConst(wireName: r'Medium')
  static const PhotoVariant medium = _$medium;

  static Serializer<PhotoVariant> get serializer => _$photoVariantSerializer;

  const PhotoVariant._(String name) : super(name);

  static BuiltSet<PhotoVariant> get values => _$values;
  static PhotoVariant valueOf(String name) => _$valueOf(name);
}

/// Optionally, enum_class can generate a mixin to go with your enum for use
/// with Angular. It exposes your enum constants as getters. So, if you mix it
/// in to your Dart component class, the values become available to the
/// corresponding Angular template.
///
/// Trigger mixin generation by writing a line like this one next to your enum.
abstract class PhotoVariantMixin = Object with _$PhotoVariantMixin;
