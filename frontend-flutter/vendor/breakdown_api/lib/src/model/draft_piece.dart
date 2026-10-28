// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'draft_piece.g.dart';

/// One constituent garment of a [`DraftOutfit`].  Screenplays rarely enumerate the garments of a standard look: they state `DR. KOCH (in OP)` or `PATIENT (in KHK)`. The pieces are therefore **context-derived** from the outfit — grounded through the outfit's quote, never individually against the chunk text (design D1).
///
/// Properties:
/// * [categoryHint] - Category the piece belongs to, when the model could name one from the canonical vocabulary (`Oberteil`, `Unterteil`, `Schuhe`, `Jacke`, `Accessoires`). Resolved against the season's categories at the API edge; an unknown hint leaves the piece uncategorized (never an error).
/// * [description] - Free-form detail from the script (condition, colour, material).
/// * [name] - Garment name as the wardrobe department would file it (`OP-Kasack`, `KHK-Hose`, `Gummistiefel`).
@BuiltValue()
abstract class DraftPiece implements Built<DraftPiece, DraftPieceBuilder> {
  /// Category the piece belongs to, when the model could name one from the canonical vocabulary (`Oberteil`, `Unterteil`, `Schuhe`, `Jacke`, `Accessoires`). Resolved against the season's categories at the API edge; an unknown hint leaves the piece uncategorized (never an error).
  @BuiltValueField(wireName: r'category_hint')
  String? get categoryHint;

  /// Free-form detail from the script (condition, colour, material).
  @BuiltValueField(wireName: r'description')
  String? get description;

  /// Garment name as the wardrobe department would file it (`OP-Kasack`, `KHK-Hose`, `Gummistiefel`).
  @BuiltValueField(wireName: r'name')
  String get name;

  DraftPiece._();

  factory DraftPiece([void updates(DraftPieceBuilder b)]) = _$DraftPiece;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(DraftPieceBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<DraftPiece> get serializer => _$DraftPieceSerializer();
}

class _$DraftPieceSerializer implements PrimitiveSerializer<DraftPiece> {
  @override
  final Iterable<Type> types = const [DraftPiece, _$DraftPiece];

  @override
  final String wireName = r'DraftPiece';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    DraftPiece object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.categoryHint != null) {
      yield r'category_hint';
      yield serializers.serialize(
        object.categoryHint,
        specifiedType: const FullType.nullable(String),
      );
    }
    if (object.description != null) {
      yield r'description';
      yield serializers.serialize(
        object.description,
        specifiedType: const FullType.nullable(String),
      );
    }
    yield r'name';
    yield serializers.serialize(
      object.name,
      specifiedType: const FullType(String),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    DraftPiece object, {
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
    required DraftPieceBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'category_hint':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.categoryHint = valueDes;
          break;
        case r'description':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.description = valueDes;
          break;
        case r'name':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.name = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  DraftPiece deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = DraftPieceBuilder();
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
