// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'uncertainty_kind.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const UncertaintyKind _$fieldAmbiguity =
    const UncertaintyKind._('fieldAmbiguity');
const UncertaintyKind _$droppedRow = const UncertaintyKind._('droppedRow');

UncertaintyKind _$valueOf(String name) {
  switch (name) {
    case 'fieldAmbiguity':
      return _$fieldAmbiguity;
    case 'droppedRow':
      return _$droppedRow;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<UncertaintyKind> _$values =
    BuiltSet<UncertaintyKind>(const <UncertaintyKind>[
  _$fieldAmbiguity,
  _$droppedRow,
]);

class _$UncertaintyKindMeta {
  const _$UncertaintyKindMeta();
  UncertaintyKind get fieldAmbiguity => _$fieldAmbiguity;
  UncertaintyKind get droppedRow => _$droppedRow;
  UncertaintyKind valueOf(String name) => _$valueOf(name);
  BuiltSet<UncertaintyKind> get values => _$values;
}

abstract class _$UncertaintyKindMixin {
  // ignore: non_constant_identifier_names
  _$UncertaintyKindMeta get UncertaintyKind => const _$UncertaintyKindMeta();
}

Serializer<UncertaintyKind> _$uncertaintyKindSerializer =
    _$UncertaintyKindSerializer();

class _$UncertaintyKindSerializer
    implements PrimitiveSerializer<UncertaintyKind> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'fieldAmbiguity': 'field_ambiguity',
    'droppedRow': 'dropped_row',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'field_ambiguity': 'fieldAmbiguity',
    'dropped_row': 'droppedRow',
  };

  @override
  final Iterable<Type> types = const <Type>[UncertaintyKind];
  @override
  final String wireName = 'UncertaintyKind';

  @override
  Object serialize(Serializers serializers, UncertaintyKind object,
          {FullType specifiedType = FullType.unspecified}) =>
      _toWire[object.name] ?? object.name;

  @override
  UncertaintyKind deserialize(Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      UncertaintyKind.valueOf(
          _fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
