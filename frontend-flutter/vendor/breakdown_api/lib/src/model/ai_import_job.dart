// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:breakdown_api/src/model/document_kind.dart';
import 'package:breakdown_api/src/model/job_status.dart';
import 'package:breakdown_api/src/model/source_format.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'ai_import_job.g.dart';

/// Operational job row. Preview blobs and errors are represented by opaque handles/summaries; credentials and document bytes are deliberately absent.
///
/// Properties:
/// * [blockId] - Opaque identifier for a `Block` aggregate.
/// * [createdAt]
/// * [dedupKey]
/// * [documentDigest]
/// * [documentKind]
/// * [id] - Opaque identifier for an operational AI import job.
/// * [lastError]
/// * [maxRetries]
/// * [previewHandle]
/// * [retries]
/// * [sourceFormat]
/// * [sourceHandle]
/// * [status]
/// * [updatedAt]
/// * [userId] - Opaque identifier for a user, wrapping the OIDC `sub` claim.  `UserId` references the authenticated principal without ever decoding, storing, or dereferencing identity attributes in `core`. The backend only trusts the IdP-issued `sub`; account lifecycle lives exclusively in the OIDC provider (ADR-010). Unlike the hierarchy ids, `UserId` is *not* a UUIDv7 — it is the raw string subject the IdP assigns.
@BuiltValue()
abstract class AiImportJob implements Built<AiImportJob, AiImportJobBuilder> {
  /// Opaque identifier for a `Block` aggregate.
  @BuiltValueField(wireName: r'block_id')
  String? get blockId;

  @BuiltValueField(wireName: r'created_at')
  DateTime get createdAt;

  @BuiltValueField(wireName: r'dedup_key')
  String get dedupKey;

  @BuiltValueField(wireName: r'document_digest')
  String get documentDigest;

  @BuiltValueField(wireName: r'document_kind')
  DocumentKind get documentKind;
  // enum documentKindEnum {  script,  schedule,  };

  /// Opaque identifier for an operational AI import job.
  @BuiltValueField(wireName: r'id')
  String get id;

  @BuiltValueField(wireName: r'last_error')
  String? get lastError;

  @BuiltValueField(wireName: r'max_retries')
  int get maxRetries;

  @BuiltValueField(wireName: r'preview_handle')
  String? get previewHandle;

  @BuiltValueField(wireName: r'retries')
  int get retries;

  @BuiltValueField(wireName: r'source_format')
  SourceFormat get sourceFormat;
  // enum sourceFormatEnum {  csv,  pdf,  plain_text,  };

  @BuiltValueField(wireName: r'source_handle')
  String get sourceHandle;

  @BuiltValueField(wireName: r'status')
  JobStatus get status;
  // enum statusEnum {  pending,  running,  succeeded,  failed,  dead_letter,  payload_unavailable,  };

  @BuiltValueField(wireName: r'updated_at')
  DateTime get updatedAt;

  /// Opaque identifier for a user, wrapping the OIDC `sub` claim.  `UserId` references the authenticated principal without ever decoding, storing, or dereferencing identity attributes in `core`. The backend only trusts the IdP-issued `sub`; account lifecycle lives exclusively in the OIDC provider (ADR-010). Unlike the hierarchy ids, `UserId` is *not* a UUIDv7 — it is the raw string subject the IdP assigns.
  @BuiltValueField(wireName: r'user_id')
  String get userId;

  AiImportJob._();

  factory AiImportJob([void updates(AiImportJobBuilder b)]) = _$AiImportJob;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(AiImportJobBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<AiImportJob> get serializer => _$AiImportJobSerializer();
}

class _$AiImportJobSerializer implements PrimitiveSerializer<AiImportJob> {
  @override
  final Iterable<Type> types = const [AiImportJob, _$AiImportJob];

  @override
  final String wireName = r'AiImportJob';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    AiImportJob object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.blockId != null) {
      yield r'block_id';
      yield serializers.serialize(
        object.blockId,
        specifiedType: const FullType.nullable(String),
      );
    }
    yield r'created_at';
    yield serializers.serialize(
      object.createdAt,
      specifiedType: const FullType(DateTime),
    );
    yield r'dedup_key';
    yield serializers.serialize(
      object.dedupKey,
      specifiedType: const FullType(String),
    );
    yield r'document_digest';
    yield serializers.serialize(
      object.documentDigest,
      specifiedType: const FullType(String),
    );
    yield r'document_kind';
    yield serializers.serialize(
      object.documentKind,
      specifiedType: const FullType(DocumentKind),
    );
    yield r'id';
    yield serializers.serialize(
      object.id,
      specifiedType: const FullType(String),
    );
    if (object.lastError != null) {
      yield r'last_error';
      yield serializers.serialize(
        object.lastError,
        specifiedType: const FullType.nullable(String),
      );
    }
    yield r'max_retries';
    yield serializers.serialize(
      object.maxRetries,
      specifiedType: const FullType(int),
    );
    if (object.previewHandle != null) {
      yield r'preview_handle';
      yield serializers.serialize(
        object.previewHandle,
        specifiedType: const FullType.nullable(String),
      );
    }
    yield r'retries';
    yield serializers.serialize(
      object.retries,
      specifiedType: const FullType(int),
    );
    yield r'source_format';
    yield serializers.serialize(
      object.sourceFormat,
      specifiedType: const FullType(SourceFormat),
    );
    yield r'source_handle';
    yield serializers.serialize(
      object.sourceHandle,
      specifiedType: const FullType(String),
    );
    yield r'status';
    yield serializers.serialize(
      object.status,
      specifiedType: const FullType(JobStatus),
    );
    yield r'updated_at';
    yield serializers.serialize(
      object.updatedAt,
      specifiedType: const FullType(DateTime),
    );
    yield r'user_id';
    yield serializers.serialize(
      object.userId,
      specifiedType: const FullType(String),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    AiImportJob object, {
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
    required AiImportJobBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'block_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.blockId = valueDes;
          break;
        case r'created_at':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.createdAt = valueDes;
          break;
        case r'dedup_key':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.dedupKey = valueDes;
          break;
        case r'document_digest':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.documentDigest = valueDes;
          break;
        case r'document_kind':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DocumentKind),
          ) as DocumentKind;
          result.documentKind = valueDes;
          break;
        case r'id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.id = valueDes;
          break;
        case r'last_error':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.lastError = valueDes;
          break;
        case r'max_retries':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.maxRetries = valueDes;
          break;
        case r'preview_handle':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.previewHandle = valueDes;
          break;
        case r'retries':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.retries = valueDes;
          break;
        case r'source_format':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(SourceFormat),
          ) as SourceFormat;
          result.sourceFormat = valueDes;
          break;
        case r'source_handle':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.sourceHandle = valueDes;
          break;
        case r'status':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(JobStatus),
          ) as JobStatus;
          result.status = valueDes;
          break;
        case r'updated_at':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.updatedAt = valueDes;
          break;
        case r'user_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.userId = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  AiImportJob deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = AiImportJobBuilder();
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
