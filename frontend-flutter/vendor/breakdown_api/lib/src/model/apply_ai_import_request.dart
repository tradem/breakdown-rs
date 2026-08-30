// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:breakdown_api/src/model/apply_mapping.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'apply_ai_import_request.g.dart';

/// ApplyAiImportRequest
///
/// Properties:
/// * [acceptAsIs]
/// * [editDistance]
/// * [episodeId] - Opaque identifier for an `Episode` aggregate.
/// * [mappings]
/// * [seriesId] - Opaque identifier for a `Series` (a show run).  `SeriesId` is an opaque UUIDv7 value type introduced by the `introduce-season-block-episode-hierarchy` change. It is the seam for a future additive `Series` aggregate: every hierarchy entity (Season, Block, Episode) references it but no `Series` aggregate exists yet.
@BuiltValue()
abstract class ApplyAiImportRequest
    implements Built<ApplyAiImportRequest, ApplyAiImportRequestBuilder> {
  @BuiltValueField(wireName: r'accept_as_is')
  bool get acceptAsIs;

  @BuiltValueField(wireName: r'edit_distance')
  int get editDistance;

  /// Opaque identifier for an `Episode` aggregate.
  @BuiltValueField(wireName: r'episode_id')
  String get episodeId;

  @BuiltValueField(wireName: r'mappings')
  BuiltList<ApplyMapping> get mappings;

  /// Opaque identifier for a `Series` (a show run).  `SeriesId` is an opaque UUIDv7 value type introduced by the `introduce-season-block-episode-hierarchy` change. It is the seam for a future additive `Series` aggregate: every hierarchy entity (Season, Block, Episode) references it but no `Series` aggregate exists yet.
  @BuiltValueField(wireName: r'series_id')
  String? get seriesId;

  ApplyAiImportRequest._();

  factory ApplyAiImportRequest([void updates(ApplyAiImportRequestBuilder b)]) =
      _$ApplyAiImportRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ApplyAiImportRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ApplyAiImportRequest> get serializer =>
      _$ApplyAiImportRequestSerializer();
}

class _$ApplyAiImportRequestSerializer
    implements PrimitiveSerializer<ApplyAiImportRequest> {
  @override
  final Iterable<Type> types = const [
    ApplyAiImportRequest,
    _$ApplyAiImportRequest
  ];

  @override
  final String wireName = r'ApplyAiImportRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ApplyAiImportRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'accept_as_is';
    yield serializers.serialize(
      object.acceptAsIs,
      specifiedType: const FullType(bool),
    );
    yield r'edit_distance';
    yield serializers.serialize(
      object.editDistance,
      specifiedType: const FullType(int),
    );
    yield r'episode_id';
    yield serializers.serialize(
      object.episodeId,
      specifiedType: const FullType(String),
    );
    yield r'mappings';
    yield serializers.serialize(
      object.mappings,
      specifiedType: const FullType(BuiltList, [FullType(ApplyMapping)]),
    );
    if (object.seriesId != null) {
      yield r'series_id';
      yield serializers.serialize(
        object.seriesId,
        specifiedType: const FullType.nullable(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    ApplyAiImportRequest object, {
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
    required ApplyAiImportRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'accept_as_is':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.acceptAsIs = valueDes;
          break;
        case r'edit_distance':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.editDistance = valueDes;
          break;
        case r'episode_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.episodeId = valueDes;
          break;
        case r'mappings':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(ApplyMapping)]),
          ) as BuiltList<ApplyMapping>;
          result.mappings.replace(valueDes);
          break;
        case r'series_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.seriesId = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  ApplyAiImportRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ApplyAiImportRequestBuilder();
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
