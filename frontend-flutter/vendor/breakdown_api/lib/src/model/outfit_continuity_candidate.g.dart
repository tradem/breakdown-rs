// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'outfit_continuity_candidate.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const OutfitContinuityCandidate _$continued =
    const OutfitContinuityCandidate._('continued');
const OutfitContinuityCandidate _$inferred =
    const OutfitContinuityCandidate._('inferred');

OutfitContinuityCandidate _$valueOf(String name) {
  switch (name) {
    case 'continued':
      return _$continued;
    case 'inferred':
      return _$inferred;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<OutfitContinuityCandidate> _$values =
    BuiltSet<OutfitContinuityCandidate>(const <OutfitContinuityCandidate>[
  _$continued,
  _$inferred,
]);

class _$OutfitContinuityCandidateMeta {
  const _$OutfitContinuityCandidateMeta();
  OutfitContinuityCandidate get continued => _$continued;
  OutfitContinuityCandidate get inferred => _$inferred;
  OutfitContinuityCandidate valueOf(String name) => _$valueOf(name);
  BuiltSet<OutfitContinuityCandidate> get values => _$values;
}

abstract class _$OutfitContinuityCandidateMixin {
  // ignore: non_constant_identifier_names
  _$OutfitContinuityCandidateMeta get OutfitContinuityCandidate =>
      const _$OutfitContinuityCandidateMeta();
}

Serializer<OutfitContinuityCandidate> _$outfitContinuityCandidateSerializer =
    _$OutfitContinuityCandidateSerializer();

class _$OutfitContinuityCandidateSerializer
    implements PrimitiveSerializer<OutfitContinuityCandidate> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'continued': 'continued',
    'inferred': 'inferred',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'continued': 'continued',
    'inferred': 'inferred',
  };

  @override
  final Iterable<Type> types = const <Type>[OutfitContinuityCandidate];
  @override
  final String wireName = 'OutfitContinuityCandidate';

  @override
  Object serialize(Serializers serializers, OutfitContinuityCandidate object,
          {FullType specifiedType = FullType.unspecified}) =>
      _toWire[object.name] ?? object.name;

  @override
  OutfitContinuityCandidate deserialize(
          Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      OutfitContinuityCandidate.valueOf(
          _fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
