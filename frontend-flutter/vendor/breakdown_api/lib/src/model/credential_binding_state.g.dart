// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'credential_binding_state.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const CredentialBindingState _$active =
    const CredentialBindingState._('active');
const CredentialBindingState _$revoked =
    const CredentialBindingState._('revoked');
const CredentialBindingState _$unreachable =
    const CredentialBindingState._('unreachable');

CredentialBindingState _$valueOf(String name) {
  switch (name) {
    case 'active':
      return _$active;
    case 'revoked':
      return _$revoked;
    case 'unreachable':
      return _$unreachable;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<CredentialBindingState> _$values =
    BuiltSet<CredentialBindingState>(const <CredentialBindingState>[
  _$active,
  _$revoked,
  _$unreachable,
]);

class _$CredentialBindingStateMeta {
  const _$CredentialBindingStateMeta();
  CredentialBindingState get active => _$active;
  CredentialBindingState get revoked => _$revoked;
  CredentialBindingState get unreachable => _$unreachable;
  CredentialBindingState valueOf(String name) => _$valueOf(name);
  BuiltSet<CredentialBindingState> get values => _$values;
}

abstract class _$CredentialBindingStateMixin {
  // ignore: non_constant_identifier_names
  _$CredentialBindingStateMeta get CredentialBindingState =>
      const _$CredentialBindingStateMeta();
}

Serializer<CredentialBindingState> _$credentialBindingStateSerializer =
    _$CredentialBindingStateSerializer();

class _$CredentialBindingStateSerializer
    implements PrimitiveSerializer<CredentialBindingState> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'active': 'active',
    'revoked': 'revoked',
    'unreachable': 'unreachable',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'active': 'active',
    'revoked': 'revoked',
    'unreachable': 'unreachable',
  };

  @override
  final Iterable<Type> types = const <Type>[CredentialBindingState];
  @override
  final String wireName = 'CredentialBindingState';

  @override
  Object serialize(Serializers serializers, CredentialBindingState object,
          {FullType specifiedType = FullType.unspecified}) =>
      _toWire[object.name] ?? object.name;

  @override
  CredentialBindingState deserialize(Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      CredentialBindingState.valueOf(
          _fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
