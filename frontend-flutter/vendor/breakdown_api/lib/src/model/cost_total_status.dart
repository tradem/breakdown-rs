// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'cost_total_status.g.dart';

/// Whether a job's total figure could be computed honestly (issue #768).  The per-import snapshot has more than one component once a Decision Model is used. A number is only offered when every recorded component is priced in **one** currency; otherwise the priced parts stay visible and the total is explicitly refused rather than misreported.
class CostTotalStatus extends EnumClass {
  @BuiltValueEnumConst(wireName: r'known')
  static const CostTotalStatus known = _$known;
  @BuiltValueEnumConst(wireName: r'incomplete')
  static const CostTotalStatus incomplete = _$incomplete;
  @BuiltValueEnumConst(wireName: r'mixed_currency')
  static const CostTotalStatus mixedCurrency = _$mixedCurrency;
  @BuiltValueEnumConst(wireName: r'unknown')
  static const CostTotalStatus unknown = _$unknown;

  static Serializer<CostTotalStatus> get serializer =>
      _$costTotalStatusSerializer;

  const CostTotalStatus._(String name) : super(name);

  static BuiltSet<CostTotalStatus> get values => _$values;
  static CostTotalStatus valueOf(String name) => _$valueOf(name);
}

/// Optionally, enum_class can generate a mixin to go with your enum for use
/// with Angular. It exposes your enum constants as getters. So, if you mix it
/// in to your Dart component class, the values become available to the
/// corresponding Angular template.
///
/// Trigger mixin generation by writing a line like this one next to your enum.
abstract class CostTotalStatusMixin = Object with _$CostTotalStatusMixin;
