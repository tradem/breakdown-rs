// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'cost_status.g.dart';

/// Whether a job's cost could be computed honestly.
class CostStatus extends EnumClass {
  @BuiltValueEnumConst(wireName: r'known')
  static const CostStatus known = _$known;
  @BuiltValueEnumConst(wireName: r'unknown')
  static const CostStatus unknown = _$unknown;
  @BuiltValueEnumConst(wireName: r'not_applicable')
  static const CostStatus notApplicable = _$notApplicable;

  static Serializer<CostStatus> get serializer => _$costStatusSerializer;

  const CostStatus._(String name) : super(name);

  static BuiltSet<CostStatus> get values => _$values;
  static CostStatus valueOf(String name) => _$valueOf(name);
}

/// Optionally, enum_class can generate a mixin to go with your enum for use
/// with Angular. It exposes your enum constants as getters. So, if you mix it
/// in to your Dart component class, the values become available to the
/// corresponding Angular template.
///
/// Trigger mixin generation by writing a line like this one next to your enum.
abstract class CostStatusMixin = Object with _$CostStatusMixin;
