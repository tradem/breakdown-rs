// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:breakdown_api/src/model/scene_source_one_of.dart';
import 'package:breakdown_api/src/model/scene_source_one_of_ai_extracted.dart';
import 'dart:core';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';
import 'package:one_of/one_of.dart';

part 'scene_source.g.dart';

/// Provenance discriminator for how a `Scene` came into existence.  `Manual` is the user-created path (REST handler). `AiExtracted` marks a scene created by the AI script import, carrying the import `document_id` (the AI job id) and the `draft_ref` as `external_ref` — the data the EU AI Act transparency provenance needs (issue #517).  `confidence` is `Option<f32>` from day one: the preview pipeline carries no model confidence value, so the AI apply records `None` instead of inventing one (in contrast to the legacy hard-coded `1.0` on `ShootingDaySource`).  Serialized as an externally-tagged enum, e.g. `{\"Manual\":null}` or `{\"AiExtracted\":{\"document_id\":...,\"external_ref\":...,\"confidence\":null}}`, which maps directly onto the `source JSONB` projection column.
///
/// Properties:
/// * [aiExtracted]
@BuiltValue()
abstract class SceneSource implements Built<SceneSource, SceneSourceBuilder> {
  /// One Of [SceneSourceOneOf], [String]
  OneOf get oneOf;

  SceneSource._();

  factory SceneSource([void updates(SceneSourceBuilder b)]) = _$SceneSource;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(SceneSourceBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<SceneSource> get serializer => _$SceneSourceSerializer();
}

class _$SceneSourceSerializer implements PrimitiveSerializer<SceneSource> {
  @override
  final Iterable<Type> types = const [SceneSource, _$SceneSource];

  @override
  final String wireName = r'SceneSource';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    SceneSource object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {}

  @override
  Object serialize(
    Serializers serializers,
    SceneSource object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final oneOf = object.oneOf;
    return serializers.serialize(oneOf.value,
        specifiedType: FullType(oneOf.valueType))!;
  }

  @override
  SceneSource deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = SceneSourceBuilder();
    Object? oneOfDataSrc;
    final targetType = const FullType(OneOf, [
      FullType(String),
      FullType(SceneSourceOneOf),
    ]);
    oneOfDataSrc = serialized;
    result.oneOf = serializers.deserialize(oneOfDataSrc,
        specifiedType: targetType) as OneOf;
    return result.build();
  }
}
