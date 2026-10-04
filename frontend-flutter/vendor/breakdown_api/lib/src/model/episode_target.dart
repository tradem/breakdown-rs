// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:breakdown_api/src/model/episode_target_one_of.dart';
import 'package:built_collection/built_collection.dart';
import 'package:breakdown_api/src/model/episode_target_one_of1.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';
import 'package:one_of/one_of.dart';

part 'episode_target.g.dart';

/// The reviewer's decision for ONE episode group of a preview (issue #581): apply the group's rows to an existing episode, or create a new one. The number comes from the document's `Ep.:` marker; the API edge pre-checks it against the series' existing episodes (409 `episode.number-already-exists`, #404 doctrine).
///
/// Properties:
/// * [episodeId] - Opaque identifier for an `Episode` aggregate.
/// * [kind]
/// * [name]
/// * [number]
@BuiltValue()
abstract class EpisodeTarget
    implements Built<EpisodeTarget, EpisodeTargetBuilder> {
  /// One Of [EpisodeTargetOneOf], [EpisodeTargetOneOf1]
  OneOf get oneOf;

  EpisodeTarget._();

  factory EpisodeTarget([void updates(EpisodeTargetBuilder b)]) =
      _$EpisodeTarget;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(EpisodeTargetBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<EpisodeTarget> get serializer =>
      _$EpisodeTargetSerializer();
}

class _$EpisodeTargetSerializer implements PrimitiveSerializer<EpisodeTarget> {
  @override
  final Iterable<Type> types = const [EpisodeTarget, _$EpisodeTarget];

  @override
  final String wireName = r'EpisodeTarget';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    EpisodeTarget object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {}

  @override
  Object serialize(
    Serializers serializers,
    EpisodeTarget object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final oneOf = object.oneOf;
    return serializers.serialize(oneOf.value,
        specifiedType: FullType(oneOf.valueType))!;
  }

  @override
  EpisodeTarget deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = EpisodeTargetBuilder();
    Object? oneOfDataSrc;
    final targetType = const FullType(OneOf, [
      FullType(EpisodeTargetOneOf),
      FullType(EpisodeTargetOneOf1),
    ]);
    oneOfDataSrc = serialized;
    result.oneOf = serializers.deserialize(oneOfDataSrc,
        specifiedType: targetType) as OneOf;
    return result.build();
  }
}

class EpisodeTargetKindEnum extends EnumClass {
  @BuiltValueEnumConst(wireName: r'create')
  static const EpisodeTargetKindEnum create = _$episodeTargetKindEnum_create;

  static Serializer<EpisodeTargetKindEnum> get serializer =>
      _$episodeTargetKindEnumSerializer;

  const EpisodeTargetKindEnum._(String name) : super(name);

  static BuiltSet<EpisodeTargetKindEnum> get values =>
      _$episodeTargetKindEnumValues;
  static EpisodeTargetKindEnum valueOf(String name) =>
      _$episodeTargetKindEnumValueOf(name);
}
