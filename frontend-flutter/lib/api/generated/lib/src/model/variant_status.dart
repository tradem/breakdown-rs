// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'variant_status.g.dart';

/// The generation status of a single photo variant.  Every variant starts as `Pending` on upload. The thumbnail saga transitions it to `Ready` on success or `Failed` on error.
class VariantStatus extends EnumClass {
  @BuiltValueEnumConst(wireName: r'Pending')
  static const VariantStatus pending = _$pending;
  @BuiltValueEnumConst(wireName: r'Ready')
  static const VariantStatus ready = _$ready;
  @BuiltValueEnumConst(wireName: r'Failed')
  static const VariantStatus failed = _$failed;

  static Serializer<VariantStatus> get serializer => _$variantStatusSerializer;

  const VariantStatus._(String name) : super(name);

  static BuiltSet<VariantStatus> get values => _$values;
  static VariantStatus valueOf(String name) => _$valueOf(name);
}

/// Optionally, enum_class can generate a mixin to go with your enum for use
/// with Angular. It exposes your enum constants as getters. So, if you mix it
/// in to your Dart component class, the values become available to the
/// corresponding Angular template.
///
/// Trigger mixin generation by writing a line like this one next to your enum.
abstract class VariantStatusMixin = Object with _$VariantStatusMixin;
