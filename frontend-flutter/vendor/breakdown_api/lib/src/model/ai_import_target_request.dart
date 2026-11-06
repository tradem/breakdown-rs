// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'ai_import_target_request.g.dart';

/// The body of `PUT /v1/ai-import/jobs/{id}/target` (issue #829).  One field on purpose: the attach names the block to write into, and the server derives everything else it stores (the block's number for the visible snapshot, its season for the authorization check). A client cannot smuggle in a season, a number or a job identity — those are server-resolved.
///
/// Properties:
/// * [blockId] - The block this job's rows will land in. Set once: repeating the same block is a `200` no-op, a different one is refused.
@BuiltValue()
abstract class AiImportTargetRequest
    implements Built<AiImportTargetRequest, AiImportTargetRequestBuilder> {
  /// The block this job's rows will land in. Set once: repeating the same block is a `200` no-op, a different one is refused.
  @BuiltValueField(wireName: r'block_id')
  String get blockId;

  AiImportTargetRequest._();

  factory AiImportTargetRequest(
      [void updates(AiImportTargetRequestBuilder b)]) = _$AiImportTargetRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(AiImportTargetRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<AiImportTargetRequest> get serializer =>
      _$AiImportTargetRequestSerializer();
}

class _$AiImportTargetRequestSerializer
    implements PrimitiveSerializer<AiImportTargetRequest> {
  @override
  final Iterable<Type> types = const [
    AiImportTargetRequest,
    _$AiImportTargetRequest
  ];

  @override
  final String wireName = r'AiImportTargetRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    AiImportTargetRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'block_id';
    yield serializers.serialize(
      object.blockId,
      specifiedType: const FullType(String),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    AiImportTargetRequest object, {
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
    required AiImportTargetRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'block_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.blockId = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  AiImportTargetRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = AiImportTargetRequestBuilder();
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
