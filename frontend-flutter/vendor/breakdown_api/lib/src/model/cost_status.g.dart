// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'cost_status.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const CostStatus _$known = const CostStatus._('known');
const CostStatus _$unknown = const CostStatus._('unknown');
const CostStatus _$notApplicable = const CostStatus._('notApplicable');

CostStatus _$valueOf(String name) {
  switch (name) {
    case 'known':
      return _$known;
    case 'unknown':
      return _$unknown;
    case 'notApplicable':
      return _$notApplicable;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<CostStatus> _$values = BuiltSet<CostStatus>(const <CostStatus>[
  _$known,
  _$unknown,
  _$notApplicable,
]);

class _$CostStatusMeta {
  const _$CostStatusMeta();
  CostStatus get known => _$known;
  CostStatus get unknown => _$unknown;
  CostStatus get notApplicable => _$notApplicable;
  CostStatus valueOf(String name) => _$valueOf(name);
  BuiltSet<CostStatus> get values => _$values;
}

abstract class _$CostStatusMixin {
  // ignore: non_constant_identifier_names
  _$CostStatusMeta get CostStatus => const _$CostStatusMeta();
}

Serializer<CostStatus> _$costStatusSerializer = _$CostStatusSerializer();

class _$CostStatusSerializer implements PrimitiveSerializer<CostStatus> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'known': 'known',
    'unknown': 'unknown',
    'notApplicable': 'not_applicable',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'known': 'known',
    'unknown': 'unknown',
    'not_applicable': 'notApplicable',
  };

  @override
  final Iterable<Type> types = const <Type>[CostStatus];
  @override
  final String wireName = 'CostStatus';

  @override
  Object serialize(Serializers serializers, CostStatus object,
          {FullType specifiedType = FullType.unspecified}) =>
      _toWire[object.name] ?? object.name;

  @override
  CostStatus deserialize(Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      CostStatus.valueOf(
          _fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
