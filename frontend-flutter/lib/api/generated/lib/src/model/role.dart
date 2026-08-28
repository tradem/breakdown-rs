// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'role.g.dart';

/// Block-scoped costume-department role.  Roles are **domain-local** and **block-scoped** (Decision 4): the same `UserId` may hold a different `Role` in two blocks of the same season because staff rotate roles at Block boundaries. The initial v1 set is `CostumeDesigner` + `WardrobeSupervisor`, plus `CostumeAssistant` which is the default role assigned to the block creator during the owner bootstrap (see `BootstrapOwner`).  **Ubiquitous Language is English.** The enum variants and their `snake_case` serde form are the canonical domain vocabulary, so events and projection rows are persisted as English strings (`\"costume_designer\"`, `\"wardrobe_supervisor\"`, `\"costume_assistant\"`).  The enum is **open for additive extension** (see `block-membership` spec, \"Initial role set\"): adding a new variant is a non-breaking change for writers, but renaming or removing an existing variant is a breaking change requiring a separate proposal. Variants are serialized by their stable `snake_case` name, so events/rows written today stay readable after a future addition.
class Role extends EnumClass {
  @BuiltValueEnumConst(wireName: r'costume_designer')
  static const Role costumeDesigner = _$costumeDesigner;
  @BuiltValueEnumConst(wireName: r'wardrobe_supervisor')
  static const Role wardrobeSupervisor = _$wardrobeSupervisor;
  @BuiltValueEnumConst(wireName: r'costume_assistant')
  static const Role costumeAssistant = _$costumeAssistant;

  static Serializer<Role> get serializer => _$roleSerializer;

  const Role._(String name) : super(name);

  static BuiltSet<Role> get values => _$values;
  static Role valueOf(String name) => _$valueOf(name);
}

/// Optionally, enum_class can generate a mixin to go with your enum for use
/// with Angular. It exposes your enum constants as getters. So, if you mix it
/// in to your Dart component class, the values become available to the
/// corresponding Angular template.
///
/// Trigger mixin generation by writing a line like this one next to your enum.
abstract class RoleMixin = Object with _$RoleMixin;
