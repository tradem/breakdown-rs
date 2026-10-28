// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'draft_outfit_origin.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const DraftOutfitOrigin _$explicitQuote =
    const DraftOutfitOrigin._('explicitQuote');
const DraftOutfitOrigin _$derived = const DraftOutfitOrigin._('derived');
const DraftOutfitOrigin _$continuedFromScene =
    const DraftOutfitOrigin._('continuedFromScene');
const DraftOutfitOrigin _$inferredFromContext =
    const DraftOutfitOrigin._('inferredFromContext');

DraftOutfitOrigin _$valueOf(String name) {
  switch (name) {
    case 'explicitQuote':
      return _$explicitQuote;
    case 'derived':
      return _$derived;
    case 'continuedFromScene':
      return _$continuedFromScene;
    case 'inferredFromContext':
      return _$inferredFromContext;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<DraftOutfitOrigin> _$values =
    BuiltSet<DraftOutfitOrigin>(const <DraftOutfitOrigin>[
  _$explicitQuote,
  _$derived,
  _$continuedFromScene,
  _$inferredFromContext,
]);

class _$DraftOutfitOriginMeta {
  const _$DraftOutfitOriginMeta();
  DraftOutfitOrigin get explicitQuote => _$explicitQuote;
  DraftOutfitOrigin get derived => _$derived;
  DraftOutfitOrigin get continuedFromScene => _$continuedFromScene;
  DraftOutfitOrigin get inferredFromContext => _$inferredFromContext;
  DraftOutfitOrigin valueOf(String name) => _$valueOf(name);
  BuiltSet<DraftOutfitOrigin> get values => _$values;
}

abstract class _$DraftOutfitOriginMixin {
  // ignore: non_constant_identifier_names
  _$DraftOutfitOriginMeta get DraftOutfitOrigin =>
      const _$DraftOutfitOriginMeta();
}

Serializer<DraftOutfitOrigin> _$draftOutfitOriginSerializer =
    _$DraftOutfitOriginSerializer();

class _$DraftOutfitOriginSerializer
    implements PrimitiveSerializer<DraftOutfitOrigin> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'explicitQuote': 'explicit_quote',
    'derived': 'derived',
    'continuedFromScene': 'continued_from_scene',
    'inferredFromContext': 'inferred_from_context',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'explicit_quote': 'explicitQuote',
    'derived': 'derived',
    'continued_from_scene': 'continuedFromScene',
    'inferred_from_context': 'inferredFromContext',
  };

  @override
  final Iterable<Type> types = const <Type>[DraftOutfitOrigin];
  @override
  final String wireName = 'DraftOutfitOrigin';

  @override
  Object serialize(Serializers serializers, DraftOutfitOrigin object,
          {FullType specifiedType = FullType.unspecified}) =>
      _toWire[object.name] ?? object.name;

  @override
  DraftOutfitOrigin deserialize(Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      DraftOutfitOrigin.valueOf(
          _fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
