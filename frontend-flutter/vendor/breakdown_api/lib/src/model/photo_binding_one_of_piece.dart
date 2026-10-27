// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'photo_binding_one_of_piece.g.dart';

/// Piece (Anprobe) photo — one garment, taken before the shoot.
///
/// Properties:
/// * [pieceId]
@BuiltValue()
abstract class PhotoBindingOneOfPiece
    implements Built<PhotoBindingOneOfPiece, PhotoBindingOneOfPieceBuilder> {
  @BuiltValueField(wireName: r'piece_id')
  String get pieceId;

  PhotoBindingOneOfPiece._();

  factory PhotoBindingOneOfPiece(
          [void updates(PhotoBindingOneOfPieceBuilder b)]) =
      _$PhotoBindingOneOfPiece;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(PhotoBindingOneOfPieceBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<PhotoBindingOneOfPiece> get serializer =>
      _$PhotoBindingOneOfPieceSerializer();
}

class _$PhotoBindingOneOfPieceSerializer
    implements PrimitiveSerializer<PhotoBindingOneOfPiece> {
  @override
  final Iterable<Type> types = const [
    PhotoBindingOneOfPiece,
    _$PhotoBindingOneOfPiece
  ];

  @override
  final String wireName = r'PhotoBindingOneOfPiece';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    PhotoBindingOneOfPiece object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'piece_id';
    yield serializers.serialize(
      object.pieceId,
      specifiedType: const FullType(String),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    PhotoBindingOneOfPiece object, {
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
    required PhotoBindingOneOfPieceBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'piece_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.pieceId = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  PhotoBindingOneOfPiece deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = PhotoBindingOneOfPieceBuilder();
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
