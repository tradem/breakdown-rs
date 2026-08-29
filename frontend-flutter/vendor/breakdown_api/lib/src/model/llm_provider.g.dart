// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'llm_provider.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const LlmProvider _$openai = const LlmProvider._('openai');
const LlmProvider _$openrouter = const LlmProvider._('openrouter');
const LlmProvider _$eurouter = const LlmProvider._('eurouter');
const LlmProvider _$neuralwatt = const LlmProvider._('neuralwatt');
const LlmProvider _$opencodeGo = const LlmProvider._('opencodeGo');
const LlmProvider _$opencode = const LlmProvider._('opencode');
const LlmProvider _$ollama = const LlmProvider._('ollama');

LlmProvider _$valueOf(String name) {
  switch (name) {
    case 'openai':
      return _$openai;
    case 'openrouter':
      return _$openrouter;
    case 'eurouter':
      return _$eurouter;
    case 'neuralwatt':
      return _$neuralwatt;
    case 'opencodeGo':
      return _$opencodeGo;
    case 'opencode':
      return _$opencode;
    case 'ollama':
      return _$ollama;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<LlmProvider> _$values =
    BuiltSet<LlmProvider>(const <LlmProvider>[
  _$openai,
  _$openrouter,
  _$eurouter,
  _$neuralwatt,
  _$opencodeGo,
  _$opencode,
  _$ollama,
]);

class _$LlmProviderMeta {
  const _$LlmProviderMeta();
  LlmProvider get openai => _$openai;
  LlmProvider get openrouter => _$openrouter;
  LlmProvider get eurouter => _$eurouter;
  LlmProvider get neuralwatt => _$neuralwatt;
  LlmProvider get opencodeGo => _$opencodeGo;
  LlmProvider get opencode => _$opencode;
  LlmProvider get ollama => _$ollama;
  LlmProvider valueOf(String name) => _$valueOf(name);
  BuiltSet<LlmProvider> get values => _$values;
}

abstract class _$LlmProviderMixin {
  // ignore: non_constant_identifier_names
  _$LlmProviderMeta get LlmProvider => const _$LlmProviderMeta();
}

Serializer<LlmProvider> _$llmProviderSerializer = _$LlmProviderSerializer();

class _$LlmProviderSerializer implements PrimitiveSerializer<LlmProvider> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'openai': 'openai',
    'openrouter': 'openrouter',
    'eurouter': 'eurouter',
    'neuralwatt': 'neuralwatt',
    'opencodeGo': 'opencode-go',
    'opencode': 'opencode',
    'ollama': 'ollama',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'openai': 'openai',
    'openrouter': 'openrouter',
    'eurouter': 'eurouter',
    'neuralwatt': 'neuralwatt',
    'opencode-go': 'opencodeGo',
    'opencode': 'opencode',
    'ollama': 'ollama',
  };

  @override
  final Iterable<Type> types = const <Type>[LlmProvider];
  @override
  final String wireName = 'LlmProvider';

  @override
  Object serialize(Serializers serializers, LlmProvider object,
          {FullType specifiedType = FullType.unspecified}) =>
      _toWire[object.name] ?? object.name;

  @override
  LlmProvider deserialize(Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      LlmProvider.valueOf(
          _fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
