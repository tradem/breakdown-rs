// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'outfit_continuity_candidate.g.dart';

/// The candidate kinds a gap can offer — at most one of each per gap.
class OutfitContinuityCandidate extends EnumClass {
  @BuiltValueEnumConst(wireName: r'continued')
  static const OutfitContinuityCandidate continued = _$continued;
  @BuiltValueEnumConst(wireName: r'inferred')
  static const OutfitContinuityCandidate inferred = _$inferred;

  static Serializer<OutfitContinuityCandidate> get serializer =>
      _$outfitContinuityCandidateSerializer;

  const OutfitContinuityCandidate._(String name) : super(name);

  static BuiltSet<OutfitContinuityCandidate> get values => _$values;
  static OutfitContinuityCandidate valueOf(String name) => _$valueOf(name);
}

/// Optionally, enum_class can generate a mixin to go with your enum for use
/// with Angular. It exposes your enum constants as getters. So, if you mix it
/// in to your Dart component class, the values become available to the
/// corresponding Angular template.
///
/// Trigger mixin generation by writing a line like this one next to your enum.
abstract class OutfitContinuityCandidateMixin = Object
    with _$OutfitContinuityCandidateMixin;
