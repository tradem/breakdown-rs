// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'create_season_request.g.dart';

/// CreateSeasonRequest
///
/// Properties:
/// * [number]
/// * [projectId] - Opaque identifier for a `Project` — the tenant-level production container.  `ProjectId` is an opaque UUIDv7 value type introduced by the `introduce-season-block-episode-hierarchy` change and renamed from `SeriesId` by issue #591 (ADR-035 D1/S1). The rename is **1:1**: the position, the UUIDv7 values and the tenant boundary are unchanged (ADR-035 B1) — only the production-form-specific *word* is gone, so the container no longer claims to be a TV show.  It remains a seam rather than an aggregate: every hierarchy entity (Season, Block, Episode) references it, but no `Project` aggregate exists yet. The children below it stay `Season`/`Block`/`Episode` until a second production form actually lands (ADR-035 D2/D3).  **Wire and storage spelling (issues #591 and #599).** The *type* is `#[serde(transparent)]` over `Uuid`, so a field typed `ProjectId` serializes as a bare UUID string. Issue #599 (ADR-035 S1, layer 3) renamed the projection columns and every wire-visible property/query parameter from `series_id` to `project_id`. Persisted *event payloads* deliberately keep the historical key — see the note on [`EventMetadata::project_id`].
/// * [title]
@BuiltValue()
abstract class CreateSeasonRequest
    implements Built<CreateSeasonRequest, CreateSeasonRequestBuilder> {
  @BuiltValueField(wireName: r'number')
  int get number;

  /// Opaque identifier for a `Project` — the tenant-level production container.  `ProjectId` is an opaque UUIDv7 value type introduced by the `introduce-season-block-episode-hierarchy` change and renamed from `SeriesId` by issue #591 (ADR-035 D1/S1). The rename is **1:1**: the position, the UUIDv7 values and the tenant boundary are unchanged (ADR-035 B1) — only the production-form-specific *word* is gone, so the container no longer claims to be a TV show.  It remains a seam rather than an aggregate: every hierarchy entity (Season, Block, Episode) references it, but no `Project` aggregate exists yet. The children below it stay `Season`/`Block`/`Episode` until a second production form actually lands (ADR-035 D2/D3).  **Wire and storage spelling (issues #591 and #599).** The *type* is `#[serde(transparent)]` over `Uuid`, so a field typed `ProjectId` serializes as a bare UUID string. Issue #599 (ADR-035 S1, layer 3) renamed the projection columns and every wire-visible property/query parameter from `series_id` to `project_id`. Persisted *event payloads* deliberately keep the historical key — see the note on [`EventMetadata::project_id`].
  @BuiltValueField(wireName: r'project_id')
  String get projectId;

  @BuiltValueField(wireName: r'title')
  String? get title;

  CreateSeasonRequest._();

  factory CreateSeasonRequest([void updates(CreateSeasonRequestBuilder b)]) =
      _$CreateSeasonRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(CreateSeasonRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<CreateSeasonRequest> get serializer =>
      _$CreateSeasonRequestSerializer();
}

class _$CreateSeasonRequestSerializer
    implements PrimitiveSerializer<CreateSeasonRequest> {
  @override
  final Iterable<Type> types = const [
    CreateSeasonRequest,
    _$CreateSeasonRequest
  ];

  @override
  final String wireName = r'CreateSeasonRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    CreateSeasonRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
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
    if (object.title != null) {
      yield r'title';
      yield serializers.serialize(
        object.title,
        specifiedType: const FullType.nullable(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    CreateSeasonRequest object, {
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
    required CreateSeasonRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
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
        case r'title':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.title = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  CreateSeasonRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = CreateSeasonRequestBuilder();
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
