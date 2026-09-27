// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'uncertainty_kind.g.dart';

/// Why the reviewer is shown an uncertainty.  The distinction is what the apply gate turns on. It did not exist before the costume work: the gate blocked a whole preview on *any* uncertainty, which is right for a field the model could not read, but would have made a single rejected costume row unappliable for an entire 85-chunk import — with a paid re-import as the only remedy, since a stored preview is immutable and a reviewer has no way to dismiss an entry.
class UncertaintyKind extends EnumClass {
  @BuiltValueEnumConst(wireName: r'field_ambiguity')
  static const UncertaintyKind fieldAmbiguity = _$fieldAmbiguity;
  @BuiltValueEnumConst(wireName: r'dropped_row')
  static const UncertaintyKind droppedRow = _$droppedRow;

  static Serializer<UncertaintyKind> get serializer =>
      _$uncertaintyKindSerializer;

  const UncertaintyKind._(String name) : super(name);

  static BuiltSet<UncertaintyKind> get values => _$values;
  static UncertaintyKind valueOf(String name) => _$valueOf(name);
}

/// Optionally, enum_class can generate a mixin to go with your enum for use
/// with Angular. It exposes your enum constants as getters. So, if you mix it
/// in to your Dart component class, the values become available to the
/// corresponding Angular template.
///
/// Trigger mixin generation by writing a line like this one next to your enum.
abstract class UncertaintyKindMixin = Object with _$UncertaintyKindMixin;
