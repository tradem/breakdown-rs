// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:breakdown_api/src/model/merged_preview.dart';
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'ai_preview_payload_one_of2.g.dart';

/// AiPreviewPayloadOneOf2
///
/// Properties:
/// * [data]
/// * [kind]
@BuiltValue()
abstract class AiPreviewPayloadOneOf2
    implements Built<AiPreviewPayloadOneOf2, AiPreviewPayloadOneOf2Builder> {
  @BuiltValueField(wireName: r'data')
  MergedPreview get data;

  @BuiltValueField(wireName: r'kind')
  AiPreviewPayloadOneOf2KindEnum get kind;
  // enum kindEnum {  merged,  };

  AiPreviewPayloadOneOf2._();

  factory AiPreviewPayloadOneOf2(
          [void updates(AiPreviewPayloadOneOf2Builder b)]) =
      _$AiPreviewPayloadOneOf2;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(AiPreviewPayloadOneOf2Builder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<AiPreviewPayloadOneOf2> get serializer =>
      _$AiPreviewPayloadOneOf2Serializer();
}

class _$AiPreviewPayloadOneOf2Serializer
    implements PrimitiveSerializer<AiPreviewPayloadOneOf2> {
  @override
  final Iterable<Type> types = const [
    AiPreviewPayloadOneOf2,
    _$AiPreviewPayloadOneOf2
  ];

  @override
  final String wireName = r'AiPreviewPayloadOneOf2';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    AiPreviewPayloadOneOf2 object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'data';
    yield serializers.serialize(
      object.data,
      specifiedType: const FullType(MergedPreview),
    );
    yield r'kind';
    yield serializers.serialize(
      object.kind,
      specifiedType: const FullType(AiPreviewPayloadOneOf2KindEnum),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    AiPreviewPayloadOneOf2 object, {
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
    required AiPreviewPayloadOneOf2Builder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'data':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(MergedPreview),
          ) as MergedPreview;
          result.data.replace(valueDes);
          break;
        case r'kind':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(AiPreviewPayloadOneOf2KindEnum),
          ) as AiPreviewPayloadOneOf2KindEnum;
          result.kind = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  AiPreviewPayloadOneOf2 deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = AiPreviewPayloadOneOf2Builder();
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

class AiPreviewPayloadOneOf2KindEnum extends EnumClass {
  @BuiltValueEnumConst(wireName: r'merged')
  static const AiPreviewPayloadOneOf2KindEnum merged =
      _$aiPreviewPayloadOneOf2KindEnum_merged;

  static Serializer<AiPreviewPayloadOneOf2KindEnum> get serializer =>
      _$aiPreviewPayloadOneOf2KindEnumSerializer;

  const AiPreviewPayloadOneOf2KindEnum._(String name) : super(name);

  static BuiltSet<AiPreviewPayloadOneOf2KindEnum> get values =>
      _$aiPreviewPayloadOneOf2KindEnumValues;
  static AiPreviewPayloadOneOf2KindEnum valueOf(String name) =>
      _$aiPreviewPayloadOneOf2KindEnumValueOf(name);
}
