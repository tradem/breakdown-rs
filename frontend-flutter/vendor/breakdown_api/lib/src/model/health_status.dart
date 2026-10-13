// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'health_status.g.dart';

/// Aggregate status of a health report, modelled on .NET's `HealthStatus`.
class HealthStatus extends EnumClass {
  @BuiltValueEnumConst(wireName: r'Healthy')
  static const HealthStatus healthy = _$healthy;
  @BuiltValueEnumConst(wireName: r'Degraded')
  static const HealthStatus degraded = _$degraded;
  @BuiltValueEnumConst(wireName: r'Unhealthy')
  static const HealthStatus unhealthy = _$unhealthy;

  static Serializer<HealthStatus> get serializer => _$healthStatusSerializer;

  const HealthStatus._(String name) : super(name);

  static BuiltSet<HealthStatus> get values => _$values;
  static HealthStatus valueOf(String name) => _$valueOf(name);
}

/// Optionally, enum_class can generate a mixin to go with your enum for use
/// with Angular. It exposes your enum constants as getters. So, if you mix it
/// in to your Dart component class, the values become available to the
/// corresponding Angular template.
///
/// Trigger mixin generation by writing a line like this one next to your enum.
abstract class HealthStatusMixin = Object with _$HealthStatusMixin;
