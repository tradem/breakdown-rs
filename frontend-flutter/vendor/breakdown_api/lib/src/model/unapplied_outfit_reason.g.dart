// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'unapplied_outfit_reason.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const UnappliedOutfitReason _$characterNotPlanned =
    const UnappliedOutfitReason._('characterNotPlanned');
const UnappliedOutfitReason _$characterUnavailable =
    const UnappliedOutfitReason._('characterUnavailable');
const UnappliedOutfitReason _$pieceRejected =
    const UnappliedOutfitReason._('pieceRejected');
const UnappliedOutfitReason _$createRejected =
    const UnappliedOutfitReason._('createRejected');
const UnappliedOutfitReason _$notesRejected =
    const UnappliedOutfitReason._('notesRejected');
const UnappliedOutfitReason _$bindingRejected =
    const UnappliedOutfitReason._('bindingRejected');
const UnappliedOutfitReason _$beatRejected =
    const UnappliedOutfitReason._('beatRejected');
const UnappliedOutfitReason _$continuityUnresolved =
    const UnappliedOutfitReason._('continuityUnresolved');

UnappliedOutfitReason _$valueOf(String name) {
  switch (name) {
    case 'characterNotPlanned':
      return _$characterNotPlanned;
    case 'characterUnavailable':
      return _$characterUnavailable;
    case 'pieceRejected':
      return _$pieceRejected;
    case 'createRejected':
      return _$createRejected;
    case 'notesRejected':
      return _$notesRejected;
    case 'bindingRejected':
      return _$bindingRejected;
    case 'beatRejected':
      return _$beatRejected;
    case 'continuityUnresolved':
      return _$continuityUnresolved;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<UnappliedOutfitReason> _$values =
    BuiltSet<UnappliedOutfitReason>(const <UnappliedOutfitReason>[
  _$characterNotPlanned,
  _$characterUnavailable,
  _$pieceRejected,
  _$createRejected,
  _$notesRejected,
  _$bindingRejected,
  _$beatRejected,
  _$continuityUnresolved,
]);

class _$UnappliedOutfitReasonMeta {
  const _$UnappliedOutfitReasonMeta();
  UnappliedOutfitReason get characterNotPlanned => _$characterNotPlanned;
  UnappliedOutfitReason get characterUnavailable => _$characterUnavailable;
  UnappliedOutfitReason get pieceRejected => _$pieceRejected;
  UnappliedOutfitReason get createRejected => _$createRejected;
  UnappliedOutfitReason get notesRejected => _$notesRejected;
  UnappliedOutfitReason get bindingRejected => _$bindingRejected;
  UnappliedOutfitReason get beatRejected => _$beatRejected;
  UnappliedOutfitReason get continuityUnresolved => _$continuityUnresolved;
  UnappliedOutfitReason valueOf(String name) => _$valueOf(name);
  BuiltSet<UnappliedOutfitReason> get values => _$values;
}

abstract class _$UnappliedOutfitReasonMixin {
  // ignore: non_constant_identifier_names
  _$UnappliedOutfitReasonMeta get UnappliedOutfitReason =>
      const _$UnappliedOutfitReasonMeta();
}

Serializer<UnappliedOutfitReason> _$unappliedOutfitReasonSerializer =
    _$UnappliedOutfitReasonSerializer();

class _$UnappliedOutfitReasonSerializer
    implements PrimitiveSerializer<UnappliedOutfitReason> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'characterNotPlanned': 'character_not_planned',
    'characterUnavailable': 'character_unavailable',
    'pieceRejected': 'piece_rejected',
    'createRejected': 'create_rejected',
    'notesRejected': 'notes_rejected',
    'bindingRejected': 'binding_rejected',
    'beatRejected': 'beat_rejected',
    'continuityUnresolved': 'continuity_unresolved',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'character_not_planned': 'characterNotPlanned',
    'character_unavailable': 'characterUnavailable',
    'piece_rejected': 'pieceRejected',
    'create_rejected': 'createRejected',
    'notes_rejected': 'notesRejected',
    'binding_rejected': 'bindingRejected',
    'beat_rejected': 'beatRejected',
    'continuity_unresolved': 'continuityUnresolved',
  };

  @override
  final Iterable<Type> types = const <Type>[UnappliedOutfitReason];
  @override
  final String wireName = 'UnappliedOutfitReason';

  @override
  Object serialize(Serializers serializers, UnappliedOutfitReason object,
          {FullType specifiedType = FullType.unspecified}) =>
      _toWire[object.name] ?? object.name;

  @override
  UnappliedOutfitReason deserialize(Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      UnappliedOutfitReason.valueOf(
          _fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
