// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'account_probe_status.g.dart';

/// What a **zero-token account probe** observed about one credential (issue #942 W4).  Deliberately three members and no free text: the status is what the client renders and what the operator reads, so it must never carry an upstream body (ADR-031 forbids raw provider `detail` on the wire). `Unknown` is a first-class answer, not a failure: the provider may expose no verified endpoint, or the read may time out — and an unknown account state must never be rendered as \"unusable\" (`#816`: an unknown answer is not a denial) nor admitted as \"usable\" by a paid-call gate.
class AccountProbeStatus extends EnumClass {
  @BuiltValueEnumConst(wireName: r'usable')
  static const AccountProbeStatus usable = _$usable;
  @BuiltValueEnumConst(wireName: r'not_usable')
  static const AccountProbeStatus notUsable = _$notUsable;
  @BuiltValueEnumConst(wireName: r'unknown')
  static const AccountProbeStatus unknown = _$unknown;

  static Serializer<AccountProbeStatus> get serializer =>
      _$accountProbeStatusSerializer;

  const AccountProbeStatus._(String name) : super(name);

  static BuiltSet<AccountProbeStatus> get values => _$values;
  static AccountProbeStatus valueOf(String name) => _$valueOf(name);
}

/// Optionally, enum_class can generate a mixin to go with your enum for use
/// with Angular. It exposes your enum constants as getters. So, if you mix it
/// in to your Dart component class, the values become available to the
/// corresponding Angular template.
///
/// Trigger mixin generation by writing a line like this one next to your enum.
abstract class AccountProbeStatusMixin = Object with _$AccountProbeStatusMixin;
