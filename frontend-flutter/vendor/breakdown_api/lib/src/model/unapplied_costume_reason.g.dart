// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'unapplied_costume_reason.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const UnappliedCostumeReason _$characterNotPlanned =
    const UnappliedCostumeReason._('characterNotPlanned');
const UnappliedCostumeReason _$characterUnavailable =
    const UnappliedCostumeReason._('characterUnavailable');
const UnappliedCostumeReason _$createRejected =
    const UnappliedCostumeReason._('createRejected');
const UnappliedCostumeReason _$notesRejected =
    const UnappliedCostumeReason._('notesRejected');
const UnappliedCostumeReason _$bindingRejected =
    const UnappliedCostumeReason._('bindingRejected');

UnappliedCostumeReason _$valueOf(String name) {
  switch (name) {
    case 'characterNotPlanned':
      return _$characterNotPlanned;
    case 'characterUnavailable':
      return _$characterUnavailable;
    case 'createRejected':
      return _$createRejected;
    case 'notesRejected':
      return _$notesRejected;
    case 'bindingRejected':
      return _$bindingRejected;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<UnappliedCostumeReason> _$values =
    BuiltSet<UnappliedCostumeReason>(const <UnappliedCostumeReason>[
  _$characterNotPlanned,
  _$characterUnavailable,
  _$createRejected,
  _$notesRejected,
  _$bindingRejected,
]);

class _$UnappliedCostumeReasonMeta {
  const _$UnappliedCostumeReasonMeta();
  UnappliedCostumeReason get characterNotPlanned => _$characterNotPlanned;
  UnappliedCostumeReason get characterUnavailable => _$characterUnavailable;
  UnappliedCostumeReason get createRejected => _$createRejected;
  UnappliedCostumeReason get notesRejected => _$notesRejected;
  UnappliedCostumeReason get bindingRejected => _$bindingRejected;
  UnappliedCostumeReason valueOf(String name) => _$valueOf(name);
  BuiltSet<UnappliedCostumeReason> get values => _$values;
}

abstract class _$UnappliedCostumeReasonMixin {
  // ignore: non_constant_identifier_names
  _$UnappliedCostumeReasonMeta get UnappliedCostumeReason =>
      const _$UnappliedCostumeReasonMeta();
}

Serializer<UnappliedCostumeReason> _$unappliedCostumeReasonSerializer =
    _$UnappliedCostumeReasonSerializer();

class _$UnappliedCostumeReasonSerializer
    implements PrimitiveSerializer<UnappliedCostumeReason> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'characterNotPlanned': 'character_not_planned',
    'characterUnavailable': 'character_unavailable',
    'createRejected': 'create_rejected',
    'notesRejected': 'notes_rejected',
    'bindingRejected': 'binding_rejected',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'character_not_planned': 'characterNotPlanned',
    'character_unavailable': 'characterUnavailable',
    'create_rejected': 'createRejected',
    'notes_rejected': 'notesRejected',
    'binding_rejected': 'bindingRejected',
  };

  @override
  final Iterable<Type> types = const <Type>[UnappliedCostumeReason];
  @override
  final String wireName = 'UnappliedCostumeReason';

  @override
  Object serialize(Serializers serializers, UnappliedCostumeReason object,
          {FullType specifiedType = FullType.unspecified}) =>
      _toWire[object.name] ?? object.name;

  @override
  UnappliedCostumeReason deserialize(Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      UnappliedCostumeReason.valueOf(
          _fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
