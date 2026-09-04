// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:breakdown_api/src/model/ai_preview_payload_one_of1.dart';
import 'package:breakdown_api/src/model/merged_preview.dart';
import 'package:breakdown_api/src/model/ai_preview_payload_one_of2.dart';
import 'package:built_collection/built_collection.dart';
import 'package:breakdown_api/src/model/ai_preview_payload_one_of.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';
import 'package:one_of/one_of.dart';

part 'ai_preview_payload.g.dart';

/// Typed preview payload served by `GET /v1/ai-import/jobs/{id}/preview` (issue #337).  Workers persist one of three shapes depending on the job's document kind and stage: `Script` (`ScriptContext`, script jobs), `Schedule` (`ShootingSchedule`, schedule jobs before the merge worker runs), or `Merged` (`MergedPreview`, schedule jobs after the merge). The externally-tagged representation lets generated clients consume preview rows structurally instead of through a runtime-validated row adapter. `MergeInput` is deliberately excluded: it is worker-internal scaffolding, never a renderable preview.
///
/// Properties:
/// * [data]
/// * [kind]
@BuiltValue()
abstract class AiPreviewPayload
    implements Built<AiPreviewPayload, AiPreviewPayloadBuilder> {
  /// One Of [AiPreviewPayloadOneOf], [AiPreviewPayloadOneOf1], [AiPreviewPayloadOneOf2]
  OneOf get oneOf;

  AiPreviewPayload._();

  factory AiPreviewPayload([void updates(AiPreviewPayloadBuilder b)]) =
      _$AiPreviewPayload;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(AiPreviewPayloadBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<AiPreviewPayload> get serializer =>
      _$AiPreviewPayloadSerializer();
}

class _$AiPreviewPayloadSerializer
    implements PrimitiveSerializer<AiPreviewPayload> {
  @override
  final Iterable<Type> types = const [AiPreviewPayload, _$AiPreviewPayload];

  @override
  final String wireName = r'AiPreviewPayload';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    AiPreviewPayload object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {}

  @override
  Object serialize(
    Serializers serializers,
    AiPreviewPayload object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final oneOf = object.oneOf;
    return serializers.serialize(oneOf.value,
        specifiedType: FullType(oneOf.valueType))!;
  }

  @override
  AiPreviewPayload deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = AiPreviewPayloadBuilder();
    Object? oneOfDataSrc;
    final targetType = const FullType(OneOf, [
      FullType(AiPreviewPayloadOneOf),
      FullType(AiPreviewPayloadOneOf1),
      FullType(AiPreviewPayloadOneOf2),
    ]);
    oneOfDataSrc = serialized;
    result.oneOf = serializers.deserialize(oneOfDataSrc,
        specifiedType: targetType) as OneOf;
    return result.build();
  }
}

class AiPreviewPayloadKindEnum extends EnumClass {
  @BuiltValueEnumConst(wireName: r'merged')
  static const AiPreviewPayloadKindEnum merged =
      _$aiPreviewPayloadKindEnum_merged;

  static Serializer<AiPreviewPayloadKindEnum> get serializer =>
      _$aiPreviewPayloadKindEnumSerializer;

  const AiPreviewPayloadKindEnum._(String name) : super(name);

  static BuiltSet<AiPreviewPayloadKindEnum> get values =>
      _$aiPreviewPayloadKindEnumValues;
  static AiPreviewPayloadKindEnum valueOf(String name) =>
      _$aiPreviewPayloadKindEnumValueOf(name);
}
