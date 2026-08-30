// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'credential_binding_state.g.dart';

/// Public binding state. It contains no secret material or ciphertext.
class CredentialBindingState extends EnumClass {
  @BuiltValueEnumConst(wireName: r'active')
  static const CredentialBindingState active = _$active;
  @BuiltValueEnumConst(wireName: r'revoked')
  static const CredentialBindingState revoked = _$revoked;
  @BuiltValueEnumConst(wireName: r'unreachable')
  static const CredentialBindingState unreachable = _$unreachable;

  static Serializer<CredentialBindingState> get serializer =>
      _$credentialBindingStateSerializer;

  const CredentialBindingState._(String name) : super(name);

  static BuiltSet<CredentialBindingState> get values => _$values;
  static CredentialBindingState valueOf(String name) => _$valueOf(name);
}

/// Optionally, enum_class can generate a mixin to go with your enum for use
/// with Angular. It exposes your enum constants as getters. So, if you mix it
/// in to your Dart component class, the values become available to the
/// corresponding Angular template.
///
/// Trigger mixin generation by writing a line like this one next to your enum.
abstract class CredentialBindingStateMixin = Object
    with _$CredentialBindingStateMixin;
