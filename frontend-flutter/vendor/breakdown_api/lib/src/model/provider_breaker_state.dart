// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'provider_breaker_state.g.dart';

/// State of a provider circuit breaker, as a **job hold** reports it (issue #871, D-A4/D-A6).  `Expired` is deliberately part of this enum but **not** of the durable breaker's own state: the `ai_import.provider_health.state` CHECK accepts `closed`, `open` and `half_open` only. A hold that ran out of its deadline keeps `state = expired` on the job row precisely so a client can tell \"the provider never came back\" from \"your retries are used up\" — the two render different copy and must never collapse into one.
class ProviderBreakerState extends EnumClass {
  @BuiltValueEnumConst(wireName: r'closed')
  static const ProviderBreakerState closed = _$closed;
  @BuiltValueEnumConst(wireName: r'open')
  static const ProviderBreakerState open = _$open;
  @BuiltValueEnumConst(wireName: r'half_open')
  static const ProviderBreakerState halfOpen = _$halfOpen;
  @BuiltValueEnumConst(wireName: r'expired')
  static const ProviderBreakerState expired = _$expired;

  static Serializer<ProviderBreakerState> get serializer =>
      _$providerBreakerStateSerializer;

  const ProviderBreakerState._(String name) : super(name);

  static BuiltSet<ProviderBreakerState> get values => _$values;
  static ProviderBreakerState valueOf(String name) => _$valueOf(name);
}

/// Optionally, enum_class can generate a mixin to go with your enum for use
/// with Angular. It exposes your enum constants as getters. So, if you mix it
/// in to your Dart component class, the values become available to the
/// corresponding Angular template.
///
/// Trigger mixin generation by writing a line like this one next to your enum.
abstract class ProviderBreakerStateMixin = Object
    with _$ProviderBreakerStateMixin;
