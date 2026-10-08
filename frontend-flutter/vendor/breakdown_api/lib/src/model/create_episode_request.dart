// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'create_episode_request.g.dart';

/// CreateEpisodeRequest
///
/// Properties:
/// * [blockId] - Opaque identifier for a `Block` aggregate.
/// * [name]
/// * [number]
/// * [projectId] - Opaque identifier for a `Project` — the tenant-level production container.  `ProjectId` is an opaque UUIDv7 value type introduced by the `introduce-season-block-episode-hierarchy` change and renamed from `SeriesId` by issue #591 (ADR-035 D1/S1). The rename is **1:1**: the position, the UUIDv7 values and the tenant boundary are unchanged (ADR-035 B1) — only the production-form-specific *word* is gone, so the container no longer claims to be a TV show.  It remains a seam rather than an aggregate: every hierarchy entity (Season, Block, Episode) references it, but no `Project` aggregate exists yet. The children below it stay `Season`/`Block`/`Episode` until a second production form actually lands (ADR-035 D2/D3).  **Wire and storage spelling (issues #591 and #599).** The *type* is `#[serde(transparent)]` over `Uuid`, so a field typed `ProjectId` serializes as a bare UUID string. Issue #599 (ADR-035 S1, layer 3) renamed the projection columns and every wire-visible property/query parameter from `series_id` to `project_id`. Persisted *event payloads* deliberately keep the historical key — see the note on [`EventMetadata::project_id`].
@BuiltValue()
abstract class CreateEpisodeRequest
    implements Built<CreateEpisodeRequest, CreateEpisodeRequestBuilder> {
  /// Opaque identifier for a `Block` aggregate.
  @BuiltValueField(wireName: r'block_id')
  String get blockId;

  @BuiltValueField(wireName: r'name')
  String? get name;

  @BuiltValueField(wireName: r'number')
  int get number;

  /// Opaque identifier for a `Project` — the tenant-level production container.  `ProjectId` is an opaque UUIDv7 value type introduced by the `introduce-season-block-episode-hierarchy` change and renamed from `SeriesId` by issue #591 (ADR-035 D1/S1). The rename is **1:1**: the position, the UUIDv7 values and the tenant boundary are unchanged (ADR-035 B1) — only the production-form-specific *word* is gone, so the container no longer claims to be a TV show.  It remains a seam rather than an aggregate: every hierarchy entity (Season, Block, Episode) references it, but no `Project` aggregate exists yet. The children below it stay `Season`/`Block`/`Episode` until a second production form actually lands (ADR-035 D2/D3).  **Wire and storage spelling (issues #591 and #599).** The *type* is `#[serde(transparent)]` over `Uuid`, so a field typed `ProjectId` serializes as a bare UUID string. Issue #599 (ADR-035 S1, layer 3) renamed the projection columns and every wire-visible property/query parameter from `series_id` to `project_id`. Persisted *event payloads* deliberately keep the historical key — see the note on [`EventMetadata::project_id`].
  @BuiltValueField(wireName: r'project_id')
  String get projectId;

  CreateEpisodeRequest._();

  factory CreateEpisodeRequest([void updates(CreateEpisodeRequestBuilder b)]) =
      _$CreateEpisodeRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(CreateEpisodeRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<CreateEpisodeRequest> get serializer =>
      _$CreateEpisodeRequestSerializer();
}

class _$CreateEpisodeRequestSerializer
    implements PrimitiveSerializer<CreateEpisodeRequest> {
  @override
  final Iterable<Type> types = const [
    CreateEpisodeRequest,
    _$CreateEpisodeRequest
  ];

  @override
  final String wireName = r'CreateEpisodeRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    CreateEpisodeRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'block_id';
    yield serializers.serialize(
      object.blockId,
      specifiedType: const FullType(String),
    );
    if (object.name != null) {
      yield r'name';
      yield serializers.serialize(
        object.name,
        specifiedType: const FullType.nullable(String),
      );
    }
    yield r'number';
    yield serializers.serialize(
      object.number,
      specifiedType: const FullType(int),
    );
    yield r'project_id';
    yield serializers.serialize(
      object.projectId,
      specifiedType: const FullType(String),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    CreateEpisodeRequest object, {
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
    required CreateEpisodeRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'block_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.blockId = valueDes;
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
            specifiedType: const FullType(int),
          ) as int;
          result.number = valueDes;
          break;
        case r'project_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.projectId = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  CreateEpisodeRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = CreateEpisodeRequestBuilder();
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
