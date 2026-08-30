// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'membership_state_kind.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const MembershipStateKind _$pending = const MembershipStateKind._('pending');
const MembershipStateKind _$active = const MembershipStateKind._('active');

MembershipStateKind _$valueOf(String name) {
  switch (name) {
    case 'pending':
      return _$pending;
    case 'active':
      return _$active;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<MembershipStateKind> _$values =
    BuiltSet<MembershipStateKind>(const <MembershipStateKind>[
  _$pending,
  _$active,
]);

class _$MembershipStateKindMeta {
  const _$MembershipStateKindMeta();
  MembershipStateKind get pending => _$pending;
  MembershipStateKind get active => _$active;
  MembershipStateKind valueOf(String name) => _$valueOf(name);
  BuiltSet<MembershipStateKind> get values => _$values;
}

abstract class _$MembershipStateKindMixin {
  // ignore: non_constant_identifier_names
  _$MembershipStateKindMeta get MembershipStateKind =>
      const _$MembershipStateKindMeta();
}

Serializer<MembershipStateKind> _$membershipStateKindSerializer =
    _$MembershipStateKindSerializer();

class _$MembershipStateKindSerializer
    implements PrimitiveSerializer<MembershipStateKind> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'pending': 'pending',
    'active': 'active',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'pending': 'pending',
    'active': 'active',
  };

  @override
  final Iterable<Type> types = const <Type>[MembershipStateKind];
  @override
  final String wireName = 'MembershipStateKind';

  @override
  Object serialize(Serializers serializers, MembershipStateKind object,
          {FullType specifiedType = FullType.unspecified}) =>
      _toWire[object.name] ?? object.name;

  @override
  MembershipStateKind deserialize(Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      MembershipStateKind.valueOf(
          _fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
