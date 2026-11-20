// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'account_probe_status.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const AccountProbeStatus _$usable = const AccountProbeStatus._('usable');
const AccountProbeStatus _$notUsable = const AccountProbeStatus._('notUsable');
const AccountProbeStatus _$unknown = const AccountProbeStatus._('unknown');

AccountProbeStatus _$valueOf(String name) {
  switch (name) {
    case 'usable':
      return _$usable;
    case 'notUsable':
      return _$notUsable;
    case 'unknown':
      return _$unknown;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<AccountProbeStatus> _$values =
    BuiltSet<AccountProbeStatus>(const <AccountProbeStatus>[
  _$usable,
  _$notUsable,
  _$unknown,
]);

class _$AccountProbeStatusMeta {
  const _$AccountProbeStatusMeta();
  AccountProbeStatus get usable => _$usable;
  AccountProbeStatus get notUsable => _$notUsable;
  AccountProbeStatus get unknown => _$unknown;
  AccountProbeStatus valueOf(String name) => _$valueOf(name);
  BuiltSet<AccountProbeStatus> get values => _$values;
}

abstract class _$AccountProbeStatusMixin {
  // ignore: non_constant_identifier_names
  _$AccountProbeStatusMeta get AccountProbeStatus =>
      const _$AccountProbeStatusMeta();
}

Serializer<AccountProbeStatus> _$accountProbeStatusSerializer =
    _$AccountProbeStatusSerializer();

class _$AccountProbeStatusSerializer
    implements PrimitiveSerializer<AccountProbeStatus> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'usable': 'usable',
    'notUsable': 'not_usable',
    'unknown': 'unknown',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'usable': 'usable',
    'not_usable': 'notUsable',
    'unknown': 'unknown',
  };

  @override
  final Iterable<Type> types = const <Type>[AccountProbeStatus];
  @override
  final String wireName = 'AccountProbeStatus';

  @override
  Object serialize(Serializers serializers, AccountProbeStatus object,
          {FullType specifiedType = FullType.unspecified}) =>
      _toWire[object.name] ?? object.name;

  @override
  AccountProbeStatus deserialize(Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      AccountProbeStatus.valueOf(
          _fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
