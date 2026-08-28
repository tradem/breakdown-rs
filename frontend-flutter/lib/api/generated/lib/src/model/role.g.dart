// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'role.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const Role _$costumeDesigner = const Role._('costumeDesigner');
const Role _$wardrobeSupervisor = const Role._('wardrobeSupervisor');
const Role _$costumeAssistant = const Role._('costumeAssistant');

Role _$valueOf(String name) {
  switch (name) {
    case 'costumeDesigner':
      return _$costumeDesigner;
    case 'wardrobeSupervisor':
      return _$wardrobeSupervisor;
    case 'costumeAssistant':
      return _$costumeAssistant;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<Role> _$values = BuiltSet<Role>(const <Role>[
  _$costumeDesigner,
  _$wardrobeSupervisor,
  _$costumeAssistant,
]);

class _$RoleMeta {
  const _$RoleMeta();
  Role get costumeDesigner => _$costumeDesigner;
  Role get wardrobeSupervisor => _$wardrobeSupervisor;
  Role get costumeAssistant => _$costumeAssistant;
  Role valueOf(String name) => _$valueOf(name);
  BuiltSet<Role> get values => _$values;
}

abstract class _$RoleMixin {
  // ignore: non_constant_identifier_names
  _$RoleMeta get Role => const _$RoleMeta();
}

Serializer<Role> _$roleSerializer = _$RoleSerializer();

class _$RoleSerializer implements PrimitiveSerializer<Role> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'costumeDesigner': 'costume_designer',
    'wardrobeSupervisor': 'wardrobe_supervisor',
    'costumeAssistant': 'costume_assistant',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'costume_designer': 'costumeDesigner',
    'wardrobe_supervisor': 'wardrobeSupervisor',
    'costume_assistant': 'costumeAssistant',
  };

  @override
  final Iterable<Type> types = const <Type>[Role];
  @override
  final String wireName = 'Role';

  @override
  Object serialize(Serializers serializers, Role object,
          {FullType specifiedType = FullType.unspecified}) =>
      _toWire[object.name] ?? object.name;

  @override
  Role deserialize(Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      Role.valueOf(
          _fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
