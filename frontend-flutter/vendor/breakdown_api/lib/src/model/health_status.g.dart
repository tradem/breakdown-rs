// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'health_status.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const HealthStatus _$healthy = const HealthStatus._('healthy');
const HealthStatus _$degraded = const HealthStatus._('degraded');
const HealthStatus _$unhealthy = const HealthStatus._('unhealthy');

HealthStatus _$valueOf(String name) {
  switch (name) {
    case 'healthy':
      return _$healthy;
    case 'degraded':
      return _$degraded;
    case 'unhealthy':
      return _$unhealthy;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<HealthStatus> _$values =
    BuiltSet<HealthStatus>(const <HealthStatus>[
  _$healthy,
  _$degraded,
  _$unhealthy,
]);

class _$HealthStatusMeta {
  const _$HealthStatusMeta();
  HealthStatus get healthy => _$healthy;
  HealthStatus get degraded => _$degraded;
  HealthStatus get unhealthy => _$unhealthy;
  HealthStatus valueOf(String name) => _$valueOf(name);
  BuiltSet<HealthStatus> get values => _$values;
}

abstract class _$HealthStatusMixin {
  // ignore: non_constant_identifier_names
  _$HealthStatusMeta get HealthStatus => const _$HealthStatusMeta();
}

Serializer<HealthStatus> _$healthStatusSerializer = _$HealthStatusSerializer();

class _$HealthStatusSerializer implements PrimitiveSerializer<HealthStatus> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'healthy': 'Healthy',
    'degraded': 'Degraded',
    'unhealthy': 'Unhealthy',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'Healthy': 'healthy',
    'Degraded': 'degraded',
    'Unhealthy': 'unhealthy',
  };

  @override
  final Iterable<Type> types = const <Type>[HealthStatus];
  @override
  final String wireName = 'HealthStatus';

  @override
  Object serialize(Serializers serializers, HealthStatus object,
          {FullType specifiedType = FullType.unspecified}) =>
      _toWire[object.name] ?? object.name;

  @override
  HealthStatus deserialize(Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      HealthStatus.valueOf(
          _fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
