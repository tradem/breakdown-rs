// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:breakdown_api/src/model/ai_preview_payload.dart';
import 'package:breakdown_api/src/model/document_kind.dart';
import 'package:breakdown_api/src/model/job_status.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'ai_import_preview_response.g.dart';

/// Typed envelope for the preview endpoint: job identity plus the parsed payload. Parsing happens server-side so a corrupt blob surfaces as `422 domain.validation` instead of an untyped blob the client must validate at runtime.
///
/// Properties:
/// * [documentKind]
/// * [jobId]
/// * [preview]
/// * [status]
@BuiltValue()
abstract class AiImportPreviewResponse
    implements Built<AiImportPreviewResponse, AiImportPreviewResponseBuilder> {
  @BuiltValueField(wireName: r'document_kind')
  DocumentKind get documentKind;
  // enum documentKindEnum {  script,  schedule,  };

  @BuiltValueField(wireName: r'job_id')
  String get jobId;

  @BuiltValueField(wireName: r'preview')
  AiPreviewPayload get preview;

  @BuiltValueField(wireName: r'status')
  JobStatus get status;
  // enum statusEnum {  pending,  running,  succeeded,  failed,  dead_letter,  payload_unavailable,  };

  AiImportPreviewResponse._();

  factory AiImportPreviewResponse(
          [void updates(AiImportPreviewResponseBuilder b)]) =
      _$AiImportPreviewResponse;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(AiImportPreviewResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<AiImportPreviewResponse> get serializer =>
      _$AiImportPreviewResponseSerializer();
}

class _$AiImportPreviewResponseSerializer
    implements PrimitiveSerializer<AiImportPreviewResponse> {
  @override
  final Iterable<Type> types = const [
    AiImportPreviewResponse,
    _$AiImportPreviewResponse
  ];

  @override
  final String wireName = r'AiImportPreviewResponse';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    AiImportPreviewResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'document_kind';
    yield serializers.serialize(
      object.documentKind,
      specifiedType: const FullType(DocumentKind),
    );
    yield r'job_id';
    yield serializers.serialize(
      object.jobId,
      specifiedType: const FullType(String),
    );
    yield r'preview';
    yield serializers.serialize(
      object.preview,
      specifiedType: const FullType(AiPreviewPayload),
    );
    yield r'status';
    yield serializers.serialize(
      object.status,
      specifiedType: const FullType(JobStatus),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    AiImportPreviewResponse object, {
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
    required AiImportPreviewResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'document_kind':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DocumentKind),
          ) as DocumentKind;
          result.documentKind = valueDes;
          break;
        case r'job_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.jobId = valueDes;
          break;
        case r'preview':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(AiPreviewPayload),
          ) as AiPreviewPayload;
          result.preview.replace(valueDes);
          break;
        case r'status':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(JobStatus),
          ) as JobStatus;
          result.status = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  AiImportPreviewResponse deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = AiImportPreviewResponseBuilder();
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
