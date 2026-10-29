// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'applied_episode.g.dart';

/// One target episode of an applied AI-import preview (issue #763).  The `applied_count` is the number of scene rows **this** job wrote into the episode, so a multi-episode import can be read at a glance instead of being summed up by the reader.
///
/// Properties:
/// * [appliedCount] - Scene rows applied into this episode.
/// * [id] - The episode the rows were applied into.
/// * [name] - Its title, when the episode has one. `None` is honest absence — an untitled episode renders by number alone.
/// * [number] - Its production-global number (the identity a user speaks in), when the apply path knew it. `None` is honest absence — never `0`, never a number read back from a projection the write path must not consult.
@BuiltValue()
abstract class AppliedEpisode
    implements Built<AppliedEpisode, AppliedEpisodeBuilder> {
  /// Scene rows applied into this episode.
  @BuiltValueField(wireName: r'applied_count')
  int get appliedCount;

  /// The episode the rows were applied into.
  @BuiltValueField(wireName: r'id')
  String get id;

  /// Its title, when the episode has one. `None` is honest absence — an untitled episode renders by number alone.
  @BuiltValueField(wireName: r'name')
  String? get name;

  /// Its production-global number (the identity a user speaks in), when the apply path knew it. `None` is honest absence — never `0`, never a number read back from a projection the write path must not consult.
  @BuiltValueField(wireName: r'number')
  int? get number;

  AppliedEpisode._();

  factory AppliedEpisode([void updates(AppliedEpisodeBuilder b)]) =
      _$AppliedEpisode;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(AppliedEpisodeBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<AppliedEpisode> get serializer =>
      _$AppliedEpisodeSerializer();
}

class _$AppliedEpisodeSerializer
    implements PrimitiveSerializer<AppliedEpisode> {
  @override
  final Iterable<Type> types = const [AppliedEpisode, _$AppliedEpisode];

  @override
  final String wireName = r'AppliedEpisode';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    AppliedEpisode object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'applied_count';
    yield serializers.serialize(
      object.appliedCount,
      specifiedType: const FullType(int),
    );
    yield r'id';
    yield serializers.serialize(
      object.id,
      specifiedType: const FullType(String),
    );
    if (object.name != null) {
      yield r'name';
      yield serializers.serialize(
        object.name,
        specifiedType: const FullType.nullable(String),
      );
    }
    if (object.number != null) {
      yield r'number';
      yield serializers.serialize(
        object.number,
        specifiedType: const FullType.nullable(int),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    AppliedEpisode object, {
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
    required AppliedEpisodeBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'applied_count':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.appliedCount = valueDes;
          break;
        case r'id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.id = valueDes;
          break;
        case r'name':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.name = valueDes;
          break;
        case r'number':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(int),
          ) as int?;
          if (valueDes == null) continue;
          result.number = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  AppliedEpisode deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = AppliedEpisodeBuilder();
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
