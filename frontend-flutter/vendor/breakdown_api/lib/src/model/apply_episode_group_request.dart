// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:breakdown_api/src/model/episode_target.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'apply_episode_group_request.g.dart';

/// One episode group's reviewer decision on the wire (issue #581). `target` reuses the core [`EpisodeTarget`] (tagged `existing` / `create`).
///
/// Properties:
/// * [episodeRef] - The group ref the preview carries on each row (`ep:<n>` / `ep-t:<title>`).
/// * [target]
@BuiltValue()
abstract class ApplyEpisodeGroupRequest
    implements
        Built<ApplyEpisodeGroupRequest, ApplyEpisodeGroupRequestBuilder> {
  /// The group ref the preview carries on each row (`ep:<n>` / `ep-t:<title>`).
  @BuiltValueField(wireName: r'episode_ref')
  String get episodeRef;

  @BuiltValueField(wireName: r'target')
  EpisodeTarget get target;

  ApplyEpisodeGroupRequest._();

  factory ApplyEpisodeGroupRequest(
          [void updates(ApplyEpisodeGroupRequestBuilder b)]) =
      _$ApplyEpisodeGroupRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ApplyEpisodeGroupRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ApplyEpisodeGroupRequest> get serializer =>
      _$ApplyEpisodeGroupRequestSerializer();
}

class _$ApplyEpisodeGroupRequestSerializer
    implements PrimitiveSerializer<ApplyEpisodeGroupRequest> {
  @override
  final Iterable<Type> types = const [
    ApplyEpisodeGroupRequest,
    _$ApplyEpisodeGroupRequest
  ];

  @override
  final String wireName = r'ApplyEpisodeGroupRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ApplyEpisodeGroupRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'episode_ref';
    yield serializers.serialize(
      object.episodeRef,
      specifiedType: const FullType(String),
    );
    yield r'target';
    yield serializers.serialize(
      object.target,
      specifiedType: const FullType(EpisodeTarget),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    ApplyEpisodeGroupRequest object, {
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
    required ApplyEpisodeGroupRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'episode_ref':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.episodeRef = valueDes;
          break;
        case r'target':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(EpisodeTarget),
          ) as EpisodeTarget;
          result.target.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  ApplyEpisodeGroupRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ApplyEpisodeGroupRequestBuilder();
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
