// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'schedule_role_modifier.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const ScheduleRoleModifier _$none = const ScheduleRoleModifier._('none');
const ScheduleRoleModifier _$dummy = const ScheduleRoleModifier._('dummy');
const ScheduleRoleModifier _$voiceOnly =
    const ScheduleRoleModifier._('voiceOnly');
const ScheduleRoleModifier _$extraOt = const ScheduleRoleModifier._('extraOt');

ScheduleRoleModifier _$valueOf(String name) {
  switch (name) {
    case 'none':
      return _$none;
    case 'dummy':
      return _$dummy;
    case 'voiceOnly':
      return _$voiceOnly;
    case 'extraOt':
      return _$extraOt;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<ScheduleRoleModifier> _$values =
    BuiltSet<ScheduleRoleModifier>(const <ScheduleRoleModifier>[
  _$none,
  _$dummy,
  _$voiceOnly,
  _$extraOt,
]);

class _$ScheduleRoleModifierMeta {
  const _$ScheduleRoleModifierMeta();
  ScheduleRoleModifier get none => _$none;
  ScheduleRoleModifier get dummy => _$dummy;
  ScheduleRoleModifier get voiceOnly => _$voiceOnly;
  ScheduleRoleModifier get extraOt => _$extraOt;
  ScheduleRoleModifier valueOf(String name) => _$valueOf(name);
  BuiltSet<ScheduleRoleModifier> get values => _$values;
}

abstract class _$ScheduleRoleModifierMixin {
  // ignore: non_constant_identifier_names
  _$ScheduleRoleModifierMeta get ScheduleRoleModifier =>
      const _$ScheduleRoleModifierMeta();
}

Serializer<ScheduleRoleModifier> _$scheduleRoleModifierSerializer =
    _$ScheduleRoleModifierSerializer();

class _$ScheduleRoleModifierSerializer
    implements PrimitiveSerializer<ScheduleRoleModifier> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'none': 'none',
    'dummy': 'dummy',
    'voiceOnly': 'voice_only',
    'extraOt': 'extra_ot',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'none': 'none',
    'dummy': 'dummy',
    'voice_only': 'voiceOnly',
    'extra_ot': 'extraOt',
  };

  @override
  final Iterable<Type> types = const <Type>[ScheduleRoleModifier];
  @override
  final String wireName = 'ScheduleRoleModifier';

  @override
  Object serialize(Serializers serializers, ScheduleRoleModifier object,
          {FullType specifiedType = FullType.unspecified}) =>
      _toWire[object.name] ?? object.name;

  @override
  ScheduleRoleModifier deserialize(Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      ScheduleRoleModifier.valueOf(
          _fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
