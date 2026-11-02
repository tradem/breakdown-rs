// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'apply_stage.g.dart';

/// Which part of an apply run is executing (issue #762).  Coarse on purpose: the per-row counter is the progress signal, and these stages only say whether rows are still being dispatched or the run is closing out (shooting-day links, the applied-episode summary).
class ApplyStage extends EnumClass {
  @BuiltValueEnumConst(wireName: r'applying')
  static const ApplyStage applying = _$applying;
  @BuiltValueEnumConst(wireName: r'finalizing')
  static const ApplyStage finalizing = _$finalizing;

  static Serializer<ApplyStage> get serializer => _$applyStageSerializer;

  const ApplyStage._(String name) : super(name);

  static BuiltSet<ApplyStage> get values => _$values;
  static ApplyStage valueOf(String name) => _$valueOf(name);
}

/// Optionally, enum_class can generate a mixin to go with your enum for use
/// with Angular. It exposes your enum constants as getters. So, if you mix it
/// in to your Dart component class, the values become available to the
/// corresponding Angular template.
///
/// Trigger mixin generation by writing a line like this one next to your enum.
abstract class ApplyStageMixin = Object with _$ApplyStageMixin;
