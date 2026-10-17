// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'currency.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const Currency _$USD = const Currency._('USD');
const Currency _$EUR = const Currency._('EUR');

Currency _$valueOf(String name) {
  switch (name) {
    case 'USD':
      return _$USD;
    case 'EUR':
      return _$EUR;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<Currency> _$values = BuiltSet<Currency>(const <Currency>[
  _$USD,
  _$EUR,
]);

class _$CurrencyMeta {
  const _$CurrencyMeta();
  Currency get USD => _$USD;
  Currency get EUR => _$EUR;
  Currency valueOf(String name) => _$valueOf(name);
  BuiltSet<Currency> get values => _$values;
}

abstract class _$CurrencyMixin {
  // ignore: non_constant_identifier_names
  _$CurrencyMeta get Currency => const _$CurrencyMeta();
}

Serializer<Currency> _$currencySerializer = _$CurrencySerializer();

class _$CurrencySerializer implements PrimitiveSerializer<Currency> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'USD': 'USD',
    'EUR': 'EUR',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'USD': 'USD',
    'EUR': 'EUR',
  };

  @override
  final Iterable<Type> types = const <Type>[Currency];
  @override
  final String wireName = 'Currency';

  @override
  Object serialize(Serializers serializers, Currency object,
          {FullType specifiedType = FullType.unspecified}) =>
      _toWire[object.name] ?? object.name;

  @override
  Currency deserialize(Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      Currency.valueOf(
          _fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
