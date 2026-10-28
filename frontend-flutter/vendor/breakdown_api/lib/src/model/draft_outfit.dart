// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:breakdown_api/src/model/draft_piece.dart';
import 'package:built_collection/built_collection.dart';
import 'package:breakdown_api/src/model/draft_outfit_origin.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'draft_outfit.g.dart';

/// One outfit extracted for a character of a draft scene.  Flat by design: the LLM has no domain ids, and the write side must not resolve ids from a read-model projection (CQRS boundary). `character_name` is matched against the same draft scene's `characters`; `source_quote` is the fragment the extraction claims to be based on, which the server verifies against the supplied chunk text before the row may reach the reviewer. The outfit's `pieces` ride along with it: a grounded outfit may carry garment names the script never wrote (design D1).
///
/// Properties:
/// * [characterName] - Character the outfit belongs to, as written in the script.
/// * [name] - Display name of the look (`OP-Kleidung`, `Mechaniker-Overall`).
/// * [notes] - Free-form notes in the script's own wording — the full description the wardrobe department needs beyond the name.
/// * [origin] - Whether the block named the look explicitly (see [`DraftOutfitOrigin`]).
/// * [pieces] - The constituent garments, `0..n`. Empty is a valid answer: the outfit is then applied as a look without pieces.
/// * [sourceQuote] - Quoted fragment of the chunk this outfit was extracted from.
@BuiltValue()
abstract class DraftOutfit implements Built<DraftOutfit, DraftOutfitBuilder> {
  /// Character the outfit belongs to, as written in the script.
  @BuiltValueField(wireName: r'character_name')
  String get characterName;

  /// Display name of the look (`OP-Kleidung`, `Mechaniker-Overall`).
  @BuiltValueField(wireName: r'name')
  String get name;

  /// Free-form notes in the script's own wording — the full description the wardrobe department needs beyond the name.
  @BuiltValueField(wireName: r'notes')
  String? get notes;

  /// Whether the block named the look explicitly (see [`DraftOutfitOrigin`]).
  @BuiltValueField(wireName: r'origin')
  DraftOutfitOrigin? get origin;

  /// The constituent garments, `0..n`. Empty is a valid answer: the outfit is then applied as a look without pieces.
  @BuiltValueField(wireName: r'pieces')
  BuiltList<DraftPiece>? get pieces;

  /// Quoted fragment of the chunk this outfit was extracted from.
  @BuiltValueField(wireName: r'source_quote')
  String get sourceQuote;

  DraftOutfit._();

  factory DraftOutfit([void updates(DraftOutfitBuilder b)]) = _$DraftOutfit;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(DraftOutfitBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<DraftOutfit> get serializer => _$DraftOutfitSerializer();
}

class _$DraftOutfitSerializer implements PrimitiveSerializer<DraftOutfit> {
  @override
  final Iterable<Type> types = const [DraftOutfit, _$DraftOutfit];

  @override
  final String wireName = r'DraftOutfit';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    DraftOutfit object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'character_name';
    yield serializers.serialize(
      object.characterName,
      specifiedType: const FullType(String),
    );
    yield r'name';
    yield serializers.serialize(
      object.name,
      specifiedType: const FullType(String),
    );
    if (object.notes != null) {
      yield r'notes';
      yield serializers.serialize(
        object.notes,
        specifiedType: const FullType.nullable(String),
      );
    }
    if (object.origin != null) {
      yield r'origin';
      yield serializers.serialize(
        object.origin,
        specifiedType: const FullType(DraftOutfitOrigin),
      );
    }
    if (object.pieces != null) {
      yield r'pieces';
      yield serializers.serialize(
        object.pieces,
        specifiedType: const FullType(BuiltList, [FullType(DraftPiece)]),
      );
    }
    yield r'source_quote';
    yield serializers.serialize(
      object.sourceQuote,
      specifiedType: const FullType(String),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    DraftOutfit object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object,
            specifiedType: specifiedType)
        .toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required DraftOutfitBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'character_name':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.characterName = valueDes;
          break;
        case r'name':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.name = valueDes;
          break;
        case r'notes':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.notes = valueDes;
          break;
        case r'origin':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(DraftOutfitOrigin),
          ) as DraftOutfitOrigin?;
          if (valueDes == null) continue;
          result.origin.replace(valueDes);
          break;
        case r'pieces':
          final valueDes = serializers.deserialize(
            value,
            specifiedType:
                const FullType.nullable(BuiltList, [FullType(DraftPiece)]),
          ) as BuiltList<DraftPiece>?;
          if (valueDes == null) continue;
          result.pieces.replace(valueDes);
          break;
        case r'source_quote':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.sourceQuote = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  DraftOutfit deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = DraftOutfitBuilder();
    final serializedList = (serialized as Iterable<Object?>).toList();
    final unhandled = <Object?>[];
    _deserializeProperties(
      serializers,
      serialized,
      specifiedType: specifiedType,
      serializedList: serializedList,
      unhandled: unhandled,
      result: result,
    );
    return result.build();
  }
}
