// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:breakdown_api/src/model/date.dart';
import 'package:breakdown_api/src/model/shooting_day_source.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'create_shooting_day_request.g.dart';

/// Request body for creating a `ShootingDay` (a Drehtag) inside an Episode.
///
/// Properties:
/// * [date] - Calendar date; `None` while planning.
/// * [episodeId] - Opaque identifier for an `Episode` aggregate.
/// * [label] - Free-form display label (e.g. \"1. Tag\").
/// * [orderKey] - Canonical ordering key within the Episode (lexicographically sortable).
/// * [source_] - Import provenance (`Manual` or `AiExtracted`).
@BuiltValue()
abstract class CreateShootingDayRequest
    implements
        Built<CreateShootingDayRequest, CreateShootingDayRequestBuilder> {
  /// Calendar date; `None` while planning.
  @BuiltValueField(wireName: r'date')
  Date? get date;

  /// Opaque identifier for an `Episode` aggregate.
  @BuiltValueField(wireName: r'episode_id')
  String get episodeId;

  /// Free-form display label (e.g. \"1. Tag\").
  @BuiltValueField(wireName: r'label')
  String? get label;

  /// Canonical ordering key within the Episode (lexicographically sortable).
  @BuiltValueField(wireName: r'order_key')
  String get orderKey;

  /// Import provenance (`Manual` or `AiExtracted`).
  @BuiltValueField(wireName: r'source')
  ShootingDaySource get source_;

  CreateShootingDayRequest._();

  factory CreateShootingDayRequest(
          [void updates(CreateShootingDayRequestBuilder b)]) =
      _$CreateShootingDayRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(CreateShootingDayRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<CreateShootingDayRequest> get serializer =>
      _$CreateShootingDayRequestSerializer();
}

class _$CreateShootingDayRequestSerializer
    implements PrimitiveSerializer<CreateShootingDayRequest> {
  @override
  final Iterable<Type> types = const [
    CreateShootingDayRequest,
    _$CreateShootingDayRequest
  ];

  @override
  final String wireName = r'CreateShootingDayRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    CreateShootingDayRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.date != null) {
      yield r'date';
      yield serializers.serialize(
        object.date,
        specifiedType: const FullType.nullable(Date),
      );
    }
    yield r'episode_id';
    yield serializers.serialize(
      object.episodeId,
      specifiedType: const FullType(String),
    );
    if (object.label != null) {
      yield r'label';
      yield serializers.serialize(
        object.label,
        specifiedType: const FullType.nullable(String),
      );
    }
    yield r'order_key';
    yield serializers.serialize(
      object.orderKey,
      specifiedType: const FullType(String),
    );
    yield r'source';
    yield serializers.serialize(
      object.source_,
      specifiedType: const FullType(ShootingDaySource),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    CreateShootingDayRequest object, {
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
    required CreateShootingDayRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'date':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(Date),
          ) as Date?;
          if (valueDes == null) continue;
          result.date = valueDes;
          break;
        case r'episode_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.episodeId = valueDes;
          break;
        case r'label':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.label = valueDes;
          break;
        case r'order_key':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.orderKey = valueDes;
          break;
        case r'source':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(ShootingDaySource),
          ) as ShootingDaySource;
          result.source_.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  CreateShootingDayRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = CreateShootingDayRequestBuilder();
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
