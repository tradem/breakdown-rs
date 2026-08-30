// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:breakdown_api/src/model/ai_import_job.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'ai_import_job_response.g.dart';

/// AiImportJobResponse
///
/// Properties:
/// * [job]
@BuiltValue()
abstract class AiImportJobResponse
    implements Built<AiImportJobResponse, AiImportJobResponseBuilder> {
  @BuiltValueField(wireName: r'job')
  AiImportJob get job;

  AiImportJobResponse._();

  factory AiImportJobResponse([void updates(AiImportJobResponseBuilder b)]) =
      _$AiImportJobResponse;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(AiImportJobResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<AiImportJobResponse> get serializer =>
      _$AiImportJobResponseSerializer();
}

class _$AiImportJobResponseSerializer
    implements PrimitiveSerializer<AiImportJobResponse> {
  @override
  final Iterable<Type> types = const [
    AiImportJobResponse,
    _$AiImportJobResponse
  ];

  @override
  final String wireName = r'AiImportJobResponse';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    AiImportJobResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'job';
    yield serializers.serialize(
      object.job,
      specifiedType: const FullType(AiImportJob),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    AiImportJobResponse object, {
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
    required AiImportJobResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'job':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(AiImportJob),
          ) as AiImportJob;
          result.job.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  AiImportJobResponse deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = AiImportJobResponseBuilder();
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
