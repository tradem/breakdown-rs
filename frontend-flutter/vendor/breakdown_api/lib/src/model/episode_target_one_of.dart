// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'episode_target_one_of.g.dart';

/// EpisodeTargetOneOf
///
/// Properties:
/// * [episodeId] - Opaque identifier for an `Episode` aggregate.
/// * [kind]
@BuiltValue()
abstract class EpisodeTargetOneOf
    implements Built<EpisodeTargetOneOf, EpisodeTargetOneOfBuilder> {
  /// Opaque identifier for an `Episode` aggregate.
  @BuiltValueField(wireName: r'episode_id')
  String get episodeId;

  @BuiltValueField(wireName: r'kind')
  EpisodeTargetOneOfKindEnum get kind;
  // enum kindEnum {  existing,  };

  EpisodeTargetOneOf._();

  factory EpisodeTargetOneOf([void updates(EpisodeTargetOneOfBuilder b)]) =
      _$EpisodeTargetOneOf;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(EpisodeTargetOneOfBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<EpisodeTargetOneOf> get serializer =>
      _$EpisodeTargetOneOfSerializer();
}

class _$EpisodeTargetOneOfSerializer
    implements PrimitiveSerializer<EpisodeTargetOneOf> {
  @override
  final Iterable<Type> types = const [EpisodeTargetOneOf, _$EpisodeTargetOneOf];

  @override
  final String wireName = r'EpisodeTargetOneOf';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    EpisodeTargetOneOf object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'episode_id';
    yield serializers.serialize(
      object.episodeId,
      specifiedType: const FullType(String),
    );
    yield r'kind';
    yield serializers.serialize(
      object.kind,
      specifiedType: const FullType(EpisodeTargetOneOfKindEnum),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    EpisodeTargetOneOf object, {
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
    required EpisodeTargetOneOfBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'episode_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.episodeId = valueDes;
          break;
        case r'kind':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(EpisodeTargetOneOfKindEnum),
          ) as EpisodeTargetOneOfKindEnum;
          result.kind = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  EpisodeTargetOneOf deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = EpisodeTargetOneOfBuilder();
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

class EpisodeTargetOneOfKindEnum extends EnumClass {
  @BuiltValueEnumConst(wireName: r'existing')
  static const EpisodeTargetOneOfKindEnum existing =
      _$episodeTargetOneOfKindEnum_existing;

  static Serializer<EpisodeTargetOneOfKindEnum> get serializer =>
      _$episodeTargetOneOfKindEnumSerializer;

  const EpisodeTargetOneOfKindEnum._(String name) : super(name);

  static BuiltSet<EpisodeTargetOneOfKindEnum> get values =>
      _$episodeTargetOneOfKindEnumValues;
  static EpisodeTargetOneOfKindEnum valueOf(String name) =>
      _$episodeTargetOneOfKindEnumValueOf(name);
}
