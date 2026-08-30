// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:breakdown_api/src/model/llm_provider.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'ai_provider_info.g.dart';

/// AiProviderInfo
///
/// Properties:
/// * [key] - Canonical lowercase path key for `/ai-import/providers/{provider}/models`.
/// * [provider]
@BuiltValue()
abstract class AiProviderInfo
    implements Built<AiProviderInfo, AiProviderInfoBuilder> {
  /// Canonical lowercase path key for `/ai-import/providers/{provider}/models`.
  @BuiltValueField(wireName: r'key')
  String get key;

  @BuiltValueField(wireName: r'provider')
  LlmProvider get provider;
  // enum providerEnum {  openai,  openrouter,  eurouter,  neuralwatt,  opencode-go,  opencode,  ollama,  };

  AiProviderInfo._();

  factory AiProviderInfo([void updates(AiProviderInfoBuilder b)]) =
      _$AiProviderInfo;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(AiProviderInfoBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<AiProviderInfo> get serializer =>
      _$AiProviderInfoSerializer();
}

class _$AiProviderInfoSerializer
    implements PrimitiveSerializer<AiProviderInfo> {
  @override
  final Iterable<Type> types = const [AiProviderInfo, _$AiProviderInfo];

  @override
  final String wireName = r'AiProviderInfo';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    AiProviderInfo object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'key';
    yield serializers.serialize(
      object.key,
      specifiedType: const FullType(String),
    );
    yield r'provider';
    yield serializers.serialize(
      object.provider,
      specifiedType: const FullType(LlmProvider),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    AiProviderInfo object, {
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
    required AiProviderInfoBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'key':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.key = valueDes;
          break;
        case r'provider':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(LlmProvider),
          ) as LlmProvider;
          result.provider = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  AiProviderInfo deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = AiProviderInfoBuilder();
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
