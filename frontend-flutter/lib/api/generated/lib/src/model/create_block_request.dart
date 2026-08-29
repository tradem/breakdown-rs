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
/// * [seriesId] - Opaque identifier for a `Series` (a show run).  `SeriesId` is an opaque UUIDv7 value type introduced by the `introduce-season-block-episode-hierarchy` change. It is the seam for a future additive `Series` aggregate: every hierarchy entity (Season, Block, Episode) references it but no `Series` aggregate exists yet.
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

  /// Opaque identifier for a `Series` (a show run).  `SeriesId` is an opaque UUIDv7 value type introduced by the `introduce-season-block-episode-hierarchy` change. It is the seam for a future additive `Series` aggregate: every hierarchy entity (Season, Block, Episode) references it but no `Series` aggregate exists yet.
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
