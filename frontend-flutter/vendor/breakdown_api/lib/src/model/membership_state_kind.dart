// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'membership_state_kind.g.dart';

/// Membership lifecycle state in the read model.  `snake_case` serialization keeps the Postgres `state` text column stable and human-readable.
class MembershipStateKind extends EnumClass {
  @BuiltValueEnumConst(wireName: r'pending')
  static const MembershipStateKind pending = _$pending;
  @BuiltValueEnumConst(wireName: r'active')
  static const MembershipStateKind active = _$active;

  static Serializer<MembershipStateKind> get serializer =>
      _$membershipStateKindSerializer;

  const MembershipStateKind._(String name) : super(name);

  static BuiltSet<MembershipStateKind> get values => _$values;
  static MembershipStateKind valueOf(String name) => _$valueOf(name);
}

/// Optionally, enum_class can generate a mixin to go with your enum for use
/// with Angular. It exposes your enum constants as getters. So, if you mix it
/// in to your Dart component class, the values become available to the
/// corresponding Angular template.
///
/// Trigger mixin generation by writing a line like this one next to your enum.
abstract class MembershipStateKindMixin = Object
    with _$MembershipStateKindMixin;
