// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/json_object.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'audit_entry.g.dart';

/// One row of the audit journal: who (`actor`) did what (`event_type` on `entity_type`/`entity_id`) when (`occurred_at`), with the event `payload`.  `series_id` is the tenant dimension prepared for per-`SeriesId` tenancy (decision 9.2) and is `NULL` in v1. `payload` is the raw event serialized as JSON (generic, so any context's events fit the same row).
///
/// Properties:
/// * [actor] - Opaque identifier for a user, wrapping the OIDC `sub` claim.  `UserId` references the authenticated principal without ever decoding, storing, or dereferencing identity attributes in `core`. The backend only trusts the IdP-issued `sub`; account lifecycle lives exclusively in the OIDC provider (ADR-010). Unlike the hierarchy ids, `UserId` is *not* a UUIDv7 — it is the raw string subject the IdP assigns.
/// * [blockId] - Opaque identifier for a `Block` aggregate.
/// * [entityId]
/// * [entityType]
/// * [eventType]
/// * [id]
/// * [occurredAt]
/// * [payload]
/// * [seriesId]
@BuiltValue()
abstract class AuditEntry implements Built<AuditEntry, AuditEntryBuilder> {
  /// Opaque identifier for a user, wrapping the OIDC `sub` claim.  `UserId` references the authenticated principal without ever decoding, storing, or dereferencing identity attributes in `core`. The backend only trusts the IdP-issued `sub`; account lifecycle lives exclusively in the OIDC provider (ADR-010). Unlike the hierarchy ids, `UserId` is *not* a UUIDv7 — it is the raw string subject the IdP assigns.
  @BuiltValueField(wireName: r'actor')
  String? get actor;

  /// Opaque identifier for a `Block` aggregate.
  @BuiltValueField(wireName: r'block_id')
  String? get blockId;

  @BuiltValueField(wireName: r'entity_id')
  String get entityId;

  @BuiltValueField(wireName: r'entity_type')
  String get entityType;

  @BuiltValueField(wireName: r'event_type')
  String get eventType;

  @BuiltValueField(wireName: r'id')
  String get id;

  @BuiltValueField(wireName: r'occurred_at')
  DateTime get occurredAt;

  @BuiltValueField(wireName: r'payload')
  JsonObject? get payload;

  @BuiltValueField(wireName: r'series_id')
  String? get seriesId;

  AuditEntry._();

  factory AuditEntry([void updates(AuditEntryBuilder b)]) = _$AuditEntry;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(AuditEntryBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<AuditEntry> get serializer => _$AuditEntrySerializer();
}

class _$AuditEntrySerializer implements PrimitiveSerializer<AuditEntry> {
  @override
  final Iterable<Type> types = const [AuditEntry, _$AuditEntry];

  @override
  final String wireName = r'AuditEntry';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    AuditEntry object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.actor != null) {
      yield r'actor';
      yield serializers.serialize(
        object.actor,
        specifiedType: const FullType.nullable(String),
      );
    }
    if (object.blockId != null) {
      yield r'block_id';
      yield serializers.serialize(
        object.blockId,
        specifiedType: const FullType.nullable(String),
      );
    }
    yield r'entity_id';
    yield serializers.serialize(
      object.entityId,
      specifiedType: const FullType(String),
    );
    yield r'entity_type';
    yield serializers.serialize(
      object.entityType,
      specifiedType: const FullType(String),
    );
    yield r'event_type';
    yield serializers.serialize(
      object.eventType,
      specifiedType: const FullType(String),
    );
    yield r'id';
    yield serializers.serialize(
      object.id,
      specifiedType: const FullType(String),
    );
    yield r'occurred_at';
    yield serializers.serialize(
      object.occurredAt,
      specifiedType: const FullType(DateTime),
    );
    yield r'payload';
    yield object.payload == null
        ? null
        : serializers.serialize(
            object.payload,
            specifiedType: const FullType.nullable(JsonObject),
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
    AuditEntry object, {
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
    required AuditEntryBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'actor':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.actor = valueDes;
          break;
        case r'block_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.blockId = valueDes;
          break;
        case r'entity_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.entityId = valueDes;
          break;
        case r'entity_type':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.entityType = valueDes;
          break;
        case r'event_type':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.eventType = valueDes;
          break;
        case r'id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.id = valueDes;
          break;
        case r'occurred_at':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.occurredAt = valueDes;
          break;
        case r'payload':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(JsonObject),
          ) as JsonObject?;
          if (valueDes == null) continue;
          result.payload = valueDes;
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
  AuditEntry deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = AuditEntryBuilder();
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
