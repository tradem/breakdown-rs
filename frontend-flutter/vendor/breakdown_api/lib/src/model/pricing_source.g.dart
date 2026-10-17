// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'pricing_source.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const PricingSource _$curatedSeed = const PricingSource._('curatedSeed');
const PricingSource _$providerLive = const PricingSource._('providerLive');
const PricingSource _$modelsDev = const PricingSource._('modelsDev');

PricingSource _$valueOf(String name) {
  switch (name) {
    case 'curatedSeed':
      return _$curatedSeed;
    case 'providerLive':
      return _$providerLive;
    case 'modelsDev':
      return _$modelsDev;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<PricingSource> _$values =
    BuiltSet<PricingSource>(const <PricingSource>[
  _$curatedSeed,
  _$providerLive,
  _$modelsDev,
]);

class _$PricingSourceMeta {
  const _$PricingSourceMeta();
  PricingSource get curatedSeed => _$curatedSeed;
  PricingSource get providerLive => _$providerLive;
  PricingSource get modelsDev => _$modelsDev;
  PricingSource valueOf(String name) => _$valueOf(name);
  BuiltSet<PricingSource> get values => _$values;
}

abstract class _$PricingSourceMixin {
  // ignore: non_constant_identifier_names
  _$PricingSourceMeta get PricingSource => const _$PricingSourceMeta();
}

Serializer<PricingSource> _$pricingSourceSerializer =
    _$PricingSourceSerializer();

class _$PricingSourceSerializer implements PrimitiveSerializer<PricingSource> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'curatedSeed': 'curated_seed',
    'providerLive': 'provider_live',
    'modelsDev': 'models_dev',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'curated_seed': 'curatedSeed',
    'provider_live': 'providerLive',
    'models_dev': 'modelsDev',
  };

  @override
  final Iterable<Type> types = const <Type>[PricingSource];
  @override
  final String wireName = 'PricingSource';

  @override
  Object serialize(Serializers serializers, PricingSource object,
          {FullType specifiedType = FullType.unspecified}) =>
      _toWire[object.name] ?? object.name;

  @override
  PricingSource deserialize(Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      PricingSource.valueOf(
          _fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
