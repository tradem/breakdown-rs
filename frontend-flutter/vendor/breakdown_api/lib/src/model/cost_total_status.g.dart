// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'cost_total_status.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const CostTotalStatus _$known = const CostTotalStatus._('known');
const CostTotalStatus _$incomplete = const CostTotalStatus._('incomplete');
const CostTotalStatus _$mixedCurrency =
    const CostTotalStatus._('mixedCurrency');
const CostTotalStatus _$unknown = const CostTotalStatus._('unknown');

CostTotalStatus _$valueOf(String name) {
  switch (name) {
    case 'known':
      return _$known;
    case 'incomplete':
      return _$incomplete;
    case 'mixedCurrency':
      return _$mixedCurrency;
    case 'unknown':
      return _$unknown;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<CostTotalStatus> _$values =
    BuiltSet<CostTotalStatus>(const <CostTotalStatus>[
  _$known,
  _$incomplete,
  _$mixedCurrency,
  _$unknown,
]);

class _$CostTotalStatusMeta {
  const _$CostTotalStatusMeta();
  CostTotalStatus get known => _$known;
  CostTotalStatus get incomplete => _$incomplete;
  CostTotalStatus get mixedCurrency => _$mixedCurrency;
  CostTotalStatus get unknown => _$unknown;
  CostTotalStatus valueOf(String name) => _$valueOf(name);
  BuiltSet<CostTotalStatus> get values => _$values;
}

abstract class _$CostTotalStatusMixin {
  // ignore: non_constant_identifier_names
  _$CostTotalStatusMeta get CostTotalStatus => const _$CostTotalStatusMeta();
}

Serializer<CostTotalStatus> _$costTotalStatusSerializer =
    _$CostTotalStatusSerializer();

class _$CostTotalStatusSerializer
    implements PrimitiveSerializer<CostTotalStatus> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'known': 'known',
    'incomplete': 'incomplete',
    'mixedCurrency': 'mixed_currency',
    'unknown': 'unknown',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'known': 'known',
    'incomplete': 'incomplete',
    'mixed_currency': 'mixedCurrency',
    'unknown': 'unknown',
  };

  @override
  final Iterable<Type> types = const <Type>[CostTotalStatus];
  @override
  final String wireName = 'CostTotalStatus';

  @override
  Object serialize(Serializers serializers, CostTotalStatus object,
          {FullType specifiedType = FullType.unspecified}) =>
      _toWire[object.name] ?? object.name;

  @override
  CostTotalStatus deserialize(Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      CostTotalStatus.valueOf(
          _fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
