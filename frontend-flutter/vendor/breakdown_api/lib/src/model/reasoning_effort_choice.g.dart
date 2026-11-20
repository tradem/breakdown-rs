// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'reasoning_effort_choice.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const ReasoningEffortChoice _$auto = const ReasoningEffortChoice._('auto');
const ReasoningEffortChoice _$minimal =
    const ReasoningEffortChoice._('minimal');
const ReasoningEffortChoice _$low = const ReasoningEffortChoice._('low');
const ReasoningEffortChoice _$medium = const ReasoningEffortChoice._('medium');
const ReasoningEffortChoice _$high = const ReasoningEffortChoice._('high');

ReasoningEffortChoice _$valueOf(String name) {
  switch (name) {
    case 'auto':
      return _$auto;
    case 'minimal':
      return _$minimal;
    case 'low':
      return _$low;
    case 'medium':
      return _$medium;
    case 'high':
      return _$high;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<ReasoningEffortChoice> _$values =
    BuiltSet<ReasoningEffortChoice>(const <ReasoningEffortChoice>[
  _$auto,
  _$minimal,
  _$low,
  _$medium,
  _$high,
]);

class _$ReasoningEffortChoiceMeta {
  const _$ReasoningEffortChoiceMeta();
  ReasoningEffortChoice get auto => _$auto;
  ReasoningEffortChoice get minimal => _$minimal;
  ReasoningEffortChoice get low => _$low;
  ReasoningEffortChoice get medium => _$medium;
  ReasoningEffortChoice get high => _$high;
  ReasoningEffortChoice valueOf(String name) => _$valueOf(name);
  BuiltSet<ReasoningEffortChoice> get values => _$values;
}

abstract class _$ReasoningEffortChoiceMixin {
  // ignore: non_constant_identifier_names
  _$ReasoningEffortChoiceMeta get ReasoningEffortChoice =>
      const _$ReasoningEffortChoiceMeta();
}

Serializer<ReasoningEffortChoice> _$reasoningEffortChoiceSerializer =
    _$ReasoningEffortChoiceSerializer();

class _$ReasoningEffortChoiceSerializer
    implements PrimitiveSerializer<ReasoningEffortChoice> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'auto': 'auto',
    'minimal': 'minimal',
    'low': 'low',
    'medium': 'medium',
    'high': 'high',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'auto': 'auto',
    'minimal': 'minimal',
    'low': 'low',
    'medium': 'medium',
    'high': 'high',
  };

  @override
  final Iterable<Type> types = const <Type>[ReasoningEffortChoice];
  @override
  final String wireName = 'ReasoningEffortChoice';

  @override
  Object serialize(Serializers serializers, ReasoningEffortChoice object,
          {FullType specifiedType = FullType.unspecified}) =>
      _toWire[object.name] ?? object.name;

  @override
  ReasoningEffortChoice deserialize(Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      ReasoningEffortChoice.valueOf(
          _fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
