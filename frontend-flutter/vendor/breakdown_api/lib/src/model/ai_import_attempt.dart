// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:breakdown_api/src/model/job_status.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'ai_import_attempt.g.dart';

/// One recorded execution attempt of an AI import job (issue #637).
///
/// Properties:
/// * [attemptNo] - 1-based attempt number, matching the job's `retries` after the attempt.
/// * [createdAt] - When the attempt was recorded.
/// * [errorSummary] - Failure summary, same text `last_error` carried for that attempt.
/// * [retryable] - Whether the attempt was classified as retryable.
/// * [status] - Job status the attempt left the job in (`failed`, `dead_letter` or `payload_unavailable`).
@BuiltValue()
abstract class AiImportAttempt
    implements Built<AiImportAttempt, AiImportAttemptBuilder> {
  /// 1-based attempt number, matching the job's `retries` after the attempt.
  @BuiltValueField(wireName: r'attempt_no')
  int get attemptNo;

  /// When the attempt was recorded.
  @BuiltValueField(wireName: r'created_at')
  DateTime get createdAt;

  /// Failure summary, same text `last_error` carried for that attempt.
  @BuiltValueField(wireName: r'error_summary')
  String? get errorSummary;

  /// Whether the attempt was classified as retryable.
  @BuiltValueField(wireName: r'retryable')
  bool get retryable;

  /// Job status the attempt left the job in (`failed`, `dead_letter` or `payload_unavailable`).
  @BuiltValueField(wireName: r'status')
  JobStatus get status;
  // enum statusEnum {  pending,  running,  succeeded,  failed,  dead_letter,  payload_unavailable,  };

  AiImportAttempt._();

  factory AiImportAttempt([void updates(AiImportAttemptBuilder b)]) =
      _$AiImportAttempt;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(AiImportAttemptBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<AiImportAttempt> get serializer =>
      _$AiImportAttemptSerializer();
}

class _$AiImportAttemptSerializer
    implements PrimitiveSerializer<AiImportAttempt> {
  @override
  final Iterable<Type> types = const [AiImportAttempt, _$AiImportAttempt];

  @override
  final String wireName = r'AiImportAttempt';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    AiImportAttempt object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'attempt_no';
    yield serializers.serialize(
      object.attemptNo,
      specifiedType: const FullType(int),
    );
    yield r'created_at';
    yield serializers.serialize(
      object.createdAt,
      specifiedType: const FullType(DateTime),
    );
    if (object.errorSummary != null) {
      yield r'error_summary';
      yield serializers.serialize(
        object.errorSummary,
        specifiedType: const FullType.nullable(String),
      );
    }
    yield r'retryable';
    yield serializers.serialize(
      object.retryable,
      specifiedType: const FullType(bool),
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
    AiImportAttempt object, {
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
    required AiImportAttemptBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'attempt_no':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.attemptNo = valueDes;
          break;
        case r'created_at':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.createdAt = valueDes;
          break;
        case r'error_summary':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.errorSummary = valueDes;
          break;
        case r'retryable':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.retryable = valueDes;
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
  AiImportAttempt deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = AiImportAttemptBuilder();
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
