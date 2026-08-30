// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'llm_provider.g.dart';

/// Curated providers. The enum is intentionally non-exhaustive so adding a provider is additive and does not break downstream matches.
class LlmProvider extends EnumClass {
  @BuiltValueEnumConst(wireName: r'openai')
  static const LlmProvider openai = _$openai;
  @BuiltValueEnumConst(wireName: r'openrouter')
  static const LlmProvider openrouter = _$openrouter;
  @BuiltValueEnumConst(wireName: r'eurouter')
  static const LlmProvider eurouter = _$eurouter;
  @BuiltValueEnumConst(wireName: r'neuralwatt')
  static const LlmProvider neuralwatt = _$neuralwatt;
  @BuiltValueEnumConst(wireName: r'opencode-go')
  static const LlmProvider opencodeGo = _$opencodeGo;
  @BuiltValueEnumConst(wireName: r'opencode')
  static const LlmProvider opencode = _$opencode;
  @BuiltValueEnumConst(wireName: r'ollama')
  static const LlmProvider ollama = _$ollama;

  static Serializer<LlmProvider> get serializer => _$llmProviderSerializer;

  const LlmProvider._(String name) : super(name);

  static BuiltSet<LlmProvider> get values => _$values;
  static LlmProvider valueOf(String name) => _$valueOf(name);
}

/// Optionally, enum_class can generate a mixin to go with your enum for use
/// with Angular. It exposes your enum constants as getters. So, if you mix it
/// in to your Dart component class, the values become available to the
/// corresponding Angular template.
///
/// Trigger mixin generation by writing a line like this one next to your enum.
abstract class LlmProviderMixin = Object with _$LlmProviderMixin;
