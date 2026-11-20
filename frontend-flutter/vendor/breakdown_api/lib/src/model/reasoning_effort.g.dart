// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'reasoning_effort.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const ReasoningEffort _$minimal = const ReasoningEffort._('minimal');
const ReasoningEffort _$low = const ReasoningEffort._('low');
const ReasoningEffort _$medium = const ReasoningEffort._('medium');
const ReasoningEffort _$high = const ReasoningEffort._('high');

ReasoningEffort _$valueOf(String name) {
  switch (name) {
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

final BuiltSet<ReasoningEffort> _$values =
    BuiltSet<ReasoningEffort>(const <ReasoningEffort>[
  _$minimal,
  _$low,
  _$medium,
  _$high,
]);

class _$ReasoningEffortMeta {
  const _$ReasoningEffortMeta();
  ReasoningEffort get minimal => _$minimal;
  ReasoningEffort get low => _$low;
  ReasoningEffort get medium => _$medium;
  ReasoningEffort get high => _$high;
  ReasoningEffort valueOf(String name) => _$valueOf(name);
  BuiltSet<ReasoningEffort> get values => _$values;
}

abstract class _$ReasoningEffortMixin {
  // ignore: non_constant_identifier_names
  _$ReasoningEffortMeta get ReasoningEffort => const _$ReasoningEffortMeta();
}

Serializer<ReasoningEffort> _$reasoningEffortSerializer =
    _$ReasoningEffortSerializer();

class _$ReasoningEffortSerializer
    implements PrimitiveSerializer<ReasoningEffort> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'minimal': 'minimal',
    'low': 'low',
    'medium': 'medium',
    'high': 'high',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'minimal': 'minimal',
    'low': 'low',
    'medium': 'medium',
    'high': 'high',
  };

  @override
  final Iterable<Type> types = const <Type>[ReasoningEffort];
  @override
  final String wireName = 'ReasoningEffort';

  @override
  Object serialize(Serializers serializers, ReasoningEffort object,
          {FullType specifiedType = FullType.unspecified}) =>
      _toWire[object.name] ?? object.name;

  @override
  ReasoningEffort deserialize(Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      ReasoningEffort.valueOf(
          _fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
