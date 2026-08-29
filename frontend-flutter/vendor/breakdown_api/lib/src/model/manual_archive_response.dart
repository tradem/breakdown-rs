// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:breakdown_api/src/model/manual_archive_job_result.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'manual_archive_response.g.dart';

/// Response body for a manual \"archive now\" request.
///
/// Properties:
/// * [jobs] - Per-kind enqueue results (dedup-aware).
@BuiltValue()
abstract class ManualArchiveResponse
    implements Built<ManualArchiveResponse, ManualArchiveResponseBuilder> {
  /// Per-kind enqueue results (dedup-aware).
  @BuiltValueField(wireName: r'jobs')
  BuiltList<ManualArchiveJobResult> get jobs;

  ManualArchiveResponse._();

  factory ManualArchiveResponse(
      [void updates(ManualArchiveResponseBuilder b)]) = _$ManualArchiveResponse;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ManualArchiveResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ManualArchiveResponse> get serializer =>
      _$ManualArchiveResponseSerializer();
}

class _$ManualArchiveResponseSerializer
    implements PrimitiveSerializer<ManualArchiveResponse> {
  @override
  final Iterable<Type> types = const [
    ManualArchiveResponse,
    _$ManualArchiveResponse
  ];

  @override
  final String wireName = r'ManualArchiveResponse';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ManualArchiveResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'jobs';
    yield serializers.serialize(
      object.jobs,
      specifiedType:
          const FullType(BuiltList, [FullType(ManualArchiveJobResult)]),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    ManualArchiveResponse object, {
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
    required ManualArchiveResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'jobs':
          final valueDes = serializers.deserialize(
            value,
            specifiedType:
                const FullType(BuiltList, [FullType(ManualArchiveJobResult)]),
          ) as BuiltList<ManualArchiveJobResult>;
          result.jobs.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  ManualArchiveResponse deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ManualArchiveResponseBuilder();
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
