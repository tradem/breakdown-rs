// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'provider_breaker_state.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const ProviderBreakerState _$closed = const ProviderBreakerState._('closed');
const ProviderBreakerState _$open = const ProviderBreakerState._('open');
const ProviderBreakerState _$halfOpen =
    const ProviderBreakerState._('halfOpen');
const ProviderBreakerState _$expired = const ProviderBreakerState._('expired');

ProviderBreakerState _$valueOf(String name) {
  switch (name) {
    case 'closed':
      return _$closed;
    case 'open':
      return _$open;
    case 'halfOpen':
      return _$halfOpen;
    case 'expired':
      return _$expired;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<ProviderBreakerState> _$values =
    BuiltSet<ProviderBreakerState>(const <ProviderBreakerState>[
  _$closed,
  _$open,
  _$halfOpen,
  _$expired,
]);

class _$ProviderBreakerStateMeta {
  const _$ProviderBreakerStateMeta();
  ProviderBreakerState get closed => _$closed;
  ProviderBreakerState get open => _$open;
  ProviderBreakerState get halfOpen => _$halfOpen;
  ProviderBreakerState get expired => _$expired;
  ProviderBreakerState valueOf(String name) => _$valueOf(name);
  BuiltSet<ProviderBreakerState> get values => _$values;
}

abstract class _$ProviderBreakerStateMixin {
  // ignore: non_constant_identifier_names
  _$ProviderBreakerStateMeta get ProviderBreakerState =>
      const _$ProviderBreakerStateMeta();
}

Serializer<ProviderBreakerState> _$providerBreakerStateSerializer =
    _$ProviderBreakerStateSerializer();

class _$ProviderBreakerStateSerializer
    implements PrimitiveSerializer<ProviderBreakerState> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'closed': 'closed',
    'open': 'open',
    'halfOpen': 'half_open',
    'expired': 'expired',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'closed': 'closed',
    'open': 'open',
    'half_open': 'halfOpen',
    'expired': 'expired',
  };

  @override
  final Iterable<Type> types = const <Type>[ProviderBreakerState];
  @override
  final String wireName = 'ProviderBreakerState';

  @override
  Object serialize(Serializers serializers, ProviderBreakerState object,
          {FullType specifiedType = FullType.unspecified}) =>
      _toWire[object.name] ?? object.name;

  @override
  ProviderBreakerState deserialize(Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      ProviderBreakerState.valueOf(
          _fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
