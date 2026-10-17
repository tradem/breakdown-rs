// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'cost_display_preference.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const CostDisplayPreference _$token = const CostDisplayPreference._('token');
const CostDisplayPreference _$energy = const CostDisplayPreference._('energy');

CostDisplayPreference _$valueOf(String name) {
  switch (name) {
    case 'token':
      return _$token;
    case 'energy':
      return _$energy;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<CostDisplayPreference> _$values =
    BuiltSet<CostDisplayPreference>(const <CostDisplayPreference>[
  _$token,
  _$energy,
]);

class _$CostDisplayPreferenceMeta {
  const _$CostDisplayPreferenceMeta();
  CostDisplayPreference get token => _$token;
  CostDisplayPreference get energy => _$energy;
  CostDisplayPreference valueOf(String name) => _$valueOf(name);
  BuiltSet<CostDisplayPreference> get values => _$values;
}

abstract class _$CostDisplayPreferenceMixin {
  // ignore: non_constant_identifier_names
  _$CostDisplayPreferenceMeta get CostDisplayPreference =>
      const _$CostDisplayPreferenceMeta();
}

Serializer<CostDisplayPreference> _$costDisplayPreferenceSerializer =
    _$CostDisplayPreferenceSerializer();

class _$CostDisplayPreferenceSerializer
    implements PrimitiveSerializer<CostDisplayPreference> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'token': 'token',
    'energy': 'energy',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'token': 'token',
    'energy': 'energy',
  };

  @override
  final Iterable<Type> types = const <Type>[CostDisplayPreference];
  @override
  final String wireName = 'CostDisplayPreference';

  @override
  Object serialize(Serializers serializers, CostDisplayPreference object,
          {FullType specifiedType = FullType.unspecified}) =>
      _toWire[object.name] ?? object.name;

  @override
  CostDisplayPreference deserialize(Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      CostDisplayPreference.valueOf(
          _fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
