// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:breakdown_api/src/model/date.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'create_block_request.g.dart';

/// CreateBlockRequest
///
/// Properties:
/// * [endDate]
/// * [number]
/// * [seasonId] - Opaque identifier for a `Season` aggregate.
/// * [seriesId] - Opaque identifier for a `Project` — the tenant-level production container.  `ProjectId` is an opaque UUIDv7 value type introduced by the `introduce-season-block-episode-hierarchy` change and renamed from `SeriesId` by issue #591 (ADR-035 D1/S1). The rename is **1:1**: the position, the UUIDv7 values and the tenant boundary are unchanged (ADR-035 B1) — only the production-form-specific *word* is gone, so the container no longer claims to be a TV show.  It remains a seam rather than an aggregate: every hierarchy entity (Season, Block, Episode) references it, but no `Project` aggregate exists yet. The children below it stay `Season`/`Block`/`Episode` until a second production form actually lands (ADR-035 D2/D3).  **Wire compatibility (issue #591, layers 2 and 3 explicitly out of the rename).** The *type* is `#[serde(transparent)]` over `Uuid`, so a field typed `ProjectId` still serializes as a bare UUID string — the JSON value is unchanged by this rename. What deliberately keeps the old spelling is the **field name** on persisted payloads: event fields and read-model view fields carry `#[serde(rename = \"series_id\")]`, and the projection columns and OpenAPI fields keep `project_id` until the dedicated layer-3 change (a breaking ADR-021 `/v2` migration).
/// * [startDate]
@BuiltValue()
abstract class CreateBlockRequest
    implements Built<CreateBlockRequest, CreateBlockRequestBuilder> {
  @BuiltValueField(wireName: r'end_date')
  Date? get endDate;

  @BuiltValueField(wireName: r'number')
  int get number;

  /// Opaque identifier for a `Season` aggregate.
  @BuiltValueField(wireName: r'season_id')
  String get seasonId;

  /// Opaque identifier for a `Project` — the tenant-level production container.  `ProjectId` is an opaque UUIDv7 value type introduced by the `introduce-season-block-episode-hierarchy` change and renamed from `SeriesId` by issue #591 (ADR-035 D1/S1). The rename is **1:1**: the position, the UUIDv7 values and the tenant boundary are unchanged (ADR-035 B1) — only the production-form-specific *word* is gone, so the container no longer claims to be a TV show.  It remains a seam rather than an aggregate: every hierarchy entity (Season, Block, Episode) references it, but no `Project` aggregate exists yet. The children below it stay `Season`/`Block`/`Episode` until a second production form actually lands (ADR-035 D2/D3).  **Wire compatibility (issue #591, layers 2 and 3 explicitly out of the rename).** The *type* is `#[serde(transparent)]` over `Uuid`, so a field typed `ProjectId` still serializes as a bare UUID string — the JSON value is unchanged by this rename. What deliberately keeps the old spelling is the **field name** on persisted payloads: event fields and read-model view fields carry `#[serde(rename = \"series_id\")]`, and the projection columns and OpenAPI fields keep `project_id` until the dedicated layer-3 change (a breaking ADR-021 `/v2` migration).
  @BuiltValueField(wireName: r'series_id')
  String get seriesId;

  @BuiltValueField(wireName: r'start_date')
  Date? get startDate;

  CreateBlockRequest._();

  factory CreateBlockRequest([void updates(CreateBlockRequestBuilder b)]) =
      _$CreateBlockRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(CreateBlockRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<CreateBlockRequest> get serializer =>
      _$CreateBlockRequestSerializer();
}

class _$CreateBlockRequestSerializer
    implements PrimitiveSerializer<CreateBlockRequest> {
  @override
  final Iterable<Type> types = const [CreateBlockRequest, _$CreateBlockRequest];

  @override
  final String wireName = r'CreateBlockRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    CreateBlockRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.endDate != null) {
      yield r'end_date';
      yield serializers.serialize(
        object.endDate,
        specifiedType: const FullType.nullable(Date),
      );
    }
    yield r'number';
    yield serializers.serialize(
      object.number,
      specifiedType: const FullType(int),
    );
    yield r'season_id';
    yield serializers.serialize(
      object.seasonId,
      specifiedType: const FullType(String),
    );
    yield r'series_id';
    yield serializers.serialize(
      object.seriesId,
      specifiedType: const FullType(String),
    );
    if (object.startDate != null) {
      yield r'start_date';
      yield serializers.serialize(
        object.startDate,
        specifiedType: const FullType.nullable(Date),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    CreateBlockRequest object, {
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
    required CreateBlockRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'end_date':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(Date),
          ) as Date?;
          if (valueDes == null) continue;
          result.endDate = valueDes;
          break;
        case r'number':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.number = valueDes;
          break;
        case r'season_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.seasonId = valueDes;
          break;
        case r'series_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.seriesId = valueDes;
          break;
        case r'start_date':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(Date),
          ) as Date?;
          if (valueDes == null) continue;
          result.startDate = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  CreateBlockRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = CreateBlockRequestBuilder();
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
