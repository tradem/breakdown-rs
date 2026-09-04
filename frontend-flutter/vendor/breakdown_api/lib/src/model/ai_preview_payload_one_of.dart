// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:breakdown_api/src/model/script_context.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'ai_preview_payload_one_of.g.dart';

/// AiPreviewPayloadOneOf
///
/// Properties:
/// * [data]
/// * [kind]
@BuiltValue()
abstract class AiPreviewPayloadOneOf
    implements Built<AiPreviewPayloadOneOf, AiPreviewPayloadOneOfBuilder> {
  @BuiltValueField(wireName: r'data')
  ScriptContext get data;

  @BuiltValueField(wireName: r'kind')
  AiPreviewPayloadOneOfKindEnum get kind;
  // enum kindEnum {  script,  };

  AiPreviewPayloadOneOf._();

  factory AiPreviewPayloadOneOf(
      [void updates(AiPreviewPayloadOneOfBuilder b)]) = _$AiPreviewPayloadOneOf;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(AiPreviewPayloadOneOfBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<AiPreviewPayloadOneOf> get serializer =>
      _$AiPreviewPayloadOneOfSerializer();
}

class _$AiPreviewPayloadOneOfSerializer
    implements PrimitiveSerializer<AiPreviewPayloadOneOf> {
  @override
  final Iterable<Type> types = const [
    AiPreviewPayloadOneOf,
    _$AiPreviewPayloadOneOf
  ];

  @override
  final String wireName = r'AiPreviewPayloadOneOf';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    AiPreviewPayloadOneOf object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'data';
    yield serializers.serialize(
      object.data,
      specifiedType: const FullType(ScriptContext),
    );
    yield r'kind';
    yield serializers.serialize(
      object.kind,
      specifiedType: const FullType(AiPreviewPayloadOneOfKindEnum),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    AiPreviewPayloadOneOf object, {
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
    required AiPreviewPayloadOneOfBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'data':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(ScriptContext),
          ) as ScriptContext;
          result.data.replace(valueDes);
          break;
        case r'kind':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(AiPreviewPayloadOneOfKindEnum),
          ) as AiPreviewPayloadOneOfKindEnum;
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
  AiPreviewPayloadOneOf deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = AiPreviewPayloadOneOfBuilder();
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

class AiPreviewPayloadOneOfKindEnum extends EnumClass {
  @BuiltValueEnumConst(wireName: r'script')
  static const AiPreviewPayloadOneOfKindEnum script =
      _$aiPreviewPayloadOneOfKindEnum_script;

  static Serializer<AiPreviewPayloadOneOfKindEnum> get serializer =>
      _$aiPreviewPayloadOneOfKindEnumSerializer;

  const AiPreviewPayloadOneOfKindEnum._(String name) : super(name);

  static BuiltSet<AiPreviewPayloadOneOfKindEnum> get values =>
      _$aiPreviewPayloadOneOfKindEnumValues;
  static AiPreviewPayloadOneOfKindEnum valueOf(String name) =>
      _$aiPreviewPayloadOneOfKindEnumValueOf(name);
}
