// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:breakdown_api/src/model/shooting_day_source_one_of_ai_extracted.dart';
import 'package:breakdown_api/src/model/shooting_day_source_one_of.dart';
import 'dart:core';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';
import 'package:one_of/one_of.dart';

part 'shooting_day_source.g.dart';

/// Provenance discriminator for how a `ShootingDay` came into existence.  `Manual` is the user-created path. `AiExtracted` reserves the shape for the future AI call-sheet extraction increment; retrofitting this onto already persisted events would be impossible, so the field exists from day one.  Serialized as an externally-tagged enum, e.g. `{\"Manual\":null}` or `{\"AiExtracted\":{\"document_id\":...,\"external_ref\":...,\"confidence\":...}}`, which maps directly onto the `source JSONB` projection column.
///
/// Properties:
/// * [aiExtracted]
@BuiltValue()
abstract class ShootingDaySource
    implements Built<ShootingDaySource, ShootingDaySourceBuilder> {
  /// One Of [ShootingDaySourceOneOf], [String]
  OneOf get oneOf;

  ShootingDaySource._();

  factory ShootingDaySource([void updates(ShootingDaySourceBuilder b)]) =
      _$ShootingDaySource;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ShootingDaySourceBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ShootingDaySource> get serializer =>
      _$ShootingDaySourceSerializer();
}

class _$ShootingDaySourceSerializer
    implements PrimitiveSerializer<ShootingDaySource> {
  @override
  final Iterable<Type> types = const [ShootingDaySource, _$ShootingDaySource];

  @override
  final String wireName = r'ShootingDaySource';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ShootingDaySource object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {}

  @override
  Object serialize(
    Serializers serializers,
    ShootingDaySource object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final oneOf = object.oneOf;
    return serializers.serialize(oneOf.value,
        specifiedType: FullType(oneOf.valueType))!;
  }

  @override
  ShootingDaySource deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ShootingDaySourceBuilder();
    Object? oneOfDataSrc;
    final targetType = const FullType(OneOf, [
      FullType(String),
      FullType(ShootingDaySourceOneOf),
    ]);
    oneOfDataSrc = serialized;
    result.oneOf = serializers.deserialize(oneOfDataSrc,
        specifiedType: targetType) as OneOf;
    return result.build();
  }
}
