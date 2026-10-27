// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'outfit_piece_view.g.dart';

/// One piece inside an outfit, in presentation order.
///
/// Properties:
/// * [categoryId]
/// * [categoryName]
/// * [name] - Piece display name; `None` on a projection miss (best-effort, never an error — a dangling reference must not fail the outfit read).
/// * [pieceId]
/// * [position] - Insertion position (ascending presentation order).
@BuiltValue()
abstract class OutfitPieceView
    implements Built<OutfitPieceView, OutfitPieceViewBuilder> {
  @BuiltValueField(wireName: r'category_id')
  String? get categoryId;

  @BuiltValueField(wireName: r'category_name')
  String? get categoryName;

  /// Piece display name; `None` on a projection miss (best-effort, never an error — a dangling reference must not fail the outfit read).
  @BuiltValueField(wireName: r'name')
  String? get name;

  @BuiltValueField(wireName: r'piece_id')
  String get pieceId;

  /// Insertion position (ascending presentation order).
  @BuiltValueField(wireName: r'position')
  int get position;

  OutfitPieceView._();

  factory OutfitPieceView([void updates(OutfitPieceViewBuilder b)]) =
      _$OutfitPieceView;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(OutfitPieceViewBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<OutfitPieceView> get serializer =>
      _$OutfitPieceViewSerializer();
}

class _$OutfitPieceViewSerializer
    implements PrimitiveSerializer<OutfitPieceView> {
  @override
  final Iterable<Type> types = const [OutfitPieceView, _$OutfitPieceView];

  @override
  final String wireName = r'OutfitPieceView';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    OutfitPieceView object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.categoryId != null) {
      yield r'category_id';
      yield serializers.serialize(
        object.categoryId,
        specifiedType: const FullType.nullable(String),
      );
    }
    if (object.categoryName != null) {
      yield r'category_name';
      yield serializers.serialize(
        object.categoryName,
        specifiedType: const FullType.nullable(String),
      );
    }
    if (object.name != null) {
      yield r'name';
      yield serializers.serialize(
        object.name,
        specifiedType: const FullType.nullable(String),
      );
    }
    yield r'piece_id';
    yield serializers.serialize(
      object.pieceId,
      specifiedType: const FullType(String),
    );
    yield r'position';
    yield serializers.serialize(
      object.position,
      specifiedType: const FullType(int),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    OutfitPieceView object, {
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
    required OutfitPieceViewBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'category_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.categoryId = valueDes;
          break;
        case r'category_name':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.categoryName = valueDes;
          break;
        case r'name':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.name = valueDes;
          break;
        case r'piece_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.pieceId = valueDes;
          break;
        case r'position':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.position = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  OutfitPieceView deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = OutfitPieceViewBuilder();
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
