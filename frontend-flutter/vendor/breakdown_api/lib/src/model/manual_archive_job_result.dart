// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'manual_archive_job_result.g.dart';

/// One job enqueue outcome.
///
/// Properties:
/// * [alreadyEnqueued]
/// * [jobId]
/// * [kind]
/// * [status]
@BuiltValue()
abstract class ManualArchiveJobResult
    implements Built<ManualArchiveJobResult, ManualArchiveJobResultBuilder> {
  @BuiltValueField(wireName: r'already_enqueued')
  bool get alreadyEnqueued;

  @BuiltValueField(wireName: r'job_id')
  String get jobId;

  @BuiltValueField(wireName: r'kind')
  String get kind;

  @BuiltValueField(wireName: r'status')
  String get status;

  ManualArchiveJobResult._();

  factory ManualArchiveJobResult(
          [void updates(ManualArchiveJobResultBuilder b)]) =
      _$ManualArchiveJobResult;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ManualArchiveJobResultBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ManualArchiveJobResult> get serializer =>
      _$ManualArchiveJobResultSerializer();
}

class _$ManualArchiveJobResultSerializer
    implements PrimitiveSerializer<ManualArchiveJobResult> {
  @override
  final Iterable<Type> types = const [
    ManualArchiveJobResult,
    _$ManualArchiveJobResult
  ];

  @override
  final String wireName = r'ManualArchiveJobResult';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ManualArchiveJobResult object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'already_enqueued';
    yield serializers.serialize(
      object.alreadyEnqueued,
      specifiedType: const FullType(bool),
    );
    yield r'job_id';
    yield serializers.serialize(
      object.jobId,
      specifiedType: const FullType(String),
    );
    yield r'kind';
    yield serializers.serialize(
      object.kind,
      specifiedType: const FullType(String),
    );
    yield r'status';
    yield serializers.serialize(
      object.status,
      specifiedType: const FullType(String),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    ManualArchiveJobResult object, {
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
    required ManualArchiveJobResultBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'already_enqueued':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.alreadyEnqueued = valueDes;
          break;
        case r'job_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.jobId = valueDes;
          break;
        case r'kind':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.kind = valueDes;
          break;
        case r'status':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
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
  ManualArchiveJobResult deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ManualArchiveJobResultBuilder();
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
